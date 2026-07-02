require "uri"

module Migration
  class DatasetUpsertService
    LEGACY_DRAFT_STATES = [
      "draft",
      "version candidate under curator review"
    ].freeze

    LEGACY_PUBLISHED_STATES = [
      "released",
      "published",
      "file embargo",
      "metadata embargo",
      "files temporarily suppressed",
      "metadata temporarily suppressed",
      "files permanently suppressed",
      "metadata permanently suppressed"
    ].freeze

    DEFAULT_SAMPLE_OWNER_UID = "legacy-import"
    DEFAULT_SAMPLE_DEPOSITOR_NAME = "Legacy Import"
    DEFAULT_SAMPLE_DEPOSITOR_EMAIL = "legacy-import@example.edu"

    Result = Struct.new(:status, :dataset_key, :identifier, :message, keyword_init: true)

    def initialize(payload:, overwrite: false, dry_run: false, require_sensitive_fields: false)
      @payload = payload
      @overwrite = overwrite
      @dry_run = dry_run
      @require_sensitive_fields = require_sensitive_fields
    end

    def call
      key = dataset_key
      identifier = payload["identifier"].presence
      return error_result("missing dataset key") if key.blank?

      existing = find_existing_dataset(key:, identifier:)
      if existing && !overwrite
        return Result.new(status: :skipped_existing, dataset_key: key, identifier: identifier, message: "dataset already exists")
      end

      return dry_run_result(existing: existing, key: key, identifier: identifier) if dry_run

      dataset = existing || Dataset.new(key: key)
      assign_dataset_attributes(dataset)
      dataset.save!
      apply_timestamps!(dataset, payload["created_at"], payload["updated_at"])

      sync_nested_records!(dataset)
      sync_token!(dataset)

      status = existing ? :updated : :created
      Result.new(status: status, dataset_key: dataset.key, identifier: dataset.identifier, message: nil)
    rescue StandardError => e
      Result.new(status: :failed, dataset_key: key, identifier: identifier, message: e.message)
    end

    private

    attr_reader :payload, :overwrite, :dry_run, :require_sensitive_fields

    def error_result(message)
      Result.new(status: :failed, dataset_key: dataset_key, identifier: payload["identifier"], message: message)
    end

    def dry_run_result(existing:, key:, identifier:)
      status = existing ? :would_update : :would_create
      Result.new(status: status, dataset_key: key, identifier: identifier, message: nil)
    end

    def find_existing_dataset(key:, identifier:)
      if identifier.present?
        Dataset.find_by(identifier: identifier) || Dataset.find_by(key: key)
      else
        Dataset.find_by(key: key)
      end
    end

    def assign_dataset_attributes(dataset)
      legacy_publication_state = normalized_legacy_publication_state(raw: payload["publication_state"])

      dataset.title = payload["title"].presence || "Untitled Dataset"
      dataset.description = payload["description"]
      dataset.identifier = payload["identifier"].presence
      dataset.publisher = payload["publisher"]
      dataset.license = payload["license"]
      dataset.keywords = payload["keywords"]
      dataset.subject = payload["subject"]
      dataset.corresponding_creator_name = payload["corresponding_creator_name"].presence
      dataset.dataset_version = payload["dataset_version"].presence
      dataset.is_test = ActiveModel::Type::Boolean.new.cast(payload["is_test"]) || false
      dataset.is_import = ActiveModel::Type::Boolean.new.cast(payload["is_import"]) || false
      dataset.embargo = normalized_embargo(raw: payload["embargo"]) || derived_embargo_from_legacy_state(legacy_publication_state: legacy_publication_state)
      dataset.legacy_publication_state = legacy_publication_state
      dataset.publication_state = publication_state_value(raw: legacy_publication_state)
      dataset.hold_state = normalized_hold_state(raw: payload["hold_state"])
      dataset.release_date = parse_date(payload["release_date"])
      dataset.tombstone_date = parse_date(payload["tombstone_date"])
      dataset.published_at = published_at_value(
        legacy_publication_state: legacy_publication_state,
        explicit_published_at: payload["published_at"],
        updated_at: payload["updated_at"],
        release_date: payload["release_date"]
      )
      dataset.nested_updated_at = parse_time(payload["nested_updated_at"])

      owner_uid, depositor_name, depositor_email = depositor_fields
      dataset.owner_uid = owner_uid
      dataset.depositor_name = depositor_name
      dataset.depositor_email = depositor_email
    end

    def depositor_fields
      if require_sensitive_fields
        owner_uid = payload["owner_uid"].presence
        depositor_name = payload["depositor_name"].presence
        depositor_email = payload["depositor_email"].presence

        if owner_uid.blank? || depositor_name.blank? || depositor_email.blank?
          raise ArgumentError, "missing sensitive depositor fields (owner_uid, depositor_name, depositor_email)"
        end

        [ owner_uid, depositor_name, depositor_email ]
      else
        owner_uid = ENV.fetch(
          "MIGRATION_SAMPLE_OWNER_UID",
          IdbConfig.fetch(:migration, :sample_owner_uid, default: DEFAULT_SAMPLE_OWNER_UID)
        )
        depositor_name = payload["corresponding_creator_name"].presence ||
                         ENV.fetch(
                           "MIGRATION_SAMPLE_DEPOSITOR_NAME",
                           IdbConfig.fetch(:migration, :sample_depositor_name, default: DEFAULT_SAMPLE_DEPOSITOR_NAME)
                         )
        depositor_email = ENV.fetch(
          "MIGRATION_SAMPLE_DEPOSITOR_EMAIL",
          IdbConfig.fetch(:migration, :sample_depositor_email, default: DEFAULT_SAMPLE_DEPOSITOR_EMAIL)
        )
        [ owner_uid, depositor_name, depositor_email ]
      end
    end

    def publication_state_value(raw:)
      value = raw.to_s.downcase
      return :draft if LEGACY_DRAFT_STATES.include?(value)
      return :published if LEGACY_PUBLISHED_STATES.include?(value)

      :draft
    end

    def normalized_legacy_publication_state(raw:)
      raw.to_s.strip.presence
    end

    def normalized_hold_state(raw:)
      raw.to_s.strip.presence
    end

    def normalized_embargo(raw:)
      normalized = raw.to_s.strip.presence
      return nil if normalized.blank? || normalized == "none"

      if normalized.include?("metadata")
        Dataset::EMBARGO_METADATA
      elsif normalized.include?("file")
        Dataset::EMBARGO_FILE
      else
        nil
      end
    end

    def derived_embargo_from_legacy_state(legacy_publication_state:)
      normalized_embargo(raw: legacy_publication_state)
    end

    def published_at_value(legacy_publication_state:, explicit_published_at:, updated_at:, release_date:)
      explicit = parse_time(explicit_published_at)
      return explicit if explicit.present?

      return nil if publication_state_value(raw: legacy_publication_state) == :draft

      parse_time(updated_at) || parse_time(release_date)
    end

    def sync_nested_records!(dataset)
      sync_collection!(dataset.creators, normalized_creators) do |record, attrs|
        record.assign_attributes(attrs)
      end

      sync_collection!(dataset.contributors, normalized_contributors) do |record, attrs|
        record.assign_attributes(attrs)
      end

      sync_collection!(dataset.funders, normalized_funders) do |record, attrs|
        record.assign_attributes(attrs)
      end

      sync_collection!(dataset.related_materials, normalized_related_materials) do |record, attrs|
        record.assign_attributes(attrs)
      end

      # Only sync datafiles when payload explicitly includes them.
      if datafiles_payload_provided?
        # Save datafiles first WITHOUT nested_items, then sync nested_items after save
        datafiles_data = normalized_datafiles
        sync_collection!(dataset.datafiles, datafiles_data) do |record, attrs|
          nested_items = attrs.delete(:nested_items)
          record.assign_attributes(attrs)
          # Don't sync nested_items here - do it after save
        end

        # Now sync nested_items for all datafiles
        dataset.datafiles.reorder(:id).each do |datafile|
          datafile_data = datafiles_data.find { |d| d[:web_id] == datafile.web_id }
          if datafile_data&.dig(:nested_items).present?
            sync_nested_items!(datafile, datafile_data[:nested_items])
          end
        end
      end

      sync_collection!(dataset.notes, normalized_notes) do |record, attrs|
        record.assign_attributes(attrs)
      end
    end

    def sync_nested_items!(datafile, nested_items_data)
      datafile.nested_items.delete_all if overwrite
      return if nested_items_data.blank?

      # Wrap entire tree build in a transaction for efficiency
      NestedItem.transaction do
        build_nested_items_tree(parent_datafile: datafile, items_data: nested_items_data, parent_item: nil)
      end
    end

    def build_nested_items_tree(parent_datafile:, items_data:, parent_item:)
      datafile_id = parent_datafile.id
      parent_id = parent_item&.id

      Array(items_data).each do |item_data|
        # Use find_or_create_by
        nested_item = NestedItem.find_or_create_by(
          datafile_id: datafile_id,
          parent_id: parent_id,
          item_name: item_data["item_name"]
        )

        # Only update if needed to reduce database writes
        if nested_item.media_type != item_data["media_type"] ||
           nested_item.size != (item_data["size"] || item_data["item_size"]) ||
           nested_item.item_path != item_data["item_path"] ||
           nested_item.is_directory != cast_boolean(item_data["is_directory"])

          nested_item.update!(
            media_type: item_data["media_type"],
            size: item_data["size"] || item_data["item_size"],
            item_path: item_data["item_path"],
            is_directory: cast_boolean(item_data["is_directory"])
          )
        end

        if item_data["children"].present?
          build_nested_items_tree(
            parent_datafile: parent_datafile,
            items_data: item_data["children"],
            parent_item: nested_item
          )
        end
      end
    end

    def cast_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def sync_collection!(association, rows)
      if overwrite
        # Use reorder to explicitly specify order for cursor-based pagination
        association.reorder(:id).destroy_all
      end
      return if rows.empty?

      rows.each do |attrs|
        row = attrs.dup
        source_created_at = row.delete(:source_created_at)
        source_updated_at = row.delete(:source_updated_at)

        record = find_existing_child(association: association, attrs: row)
        record ||= association.build
        yield(record, row)
        begin
          record.save!
        rescue StandardError => e
          Rails.logger.error("Failed to save #{association.klass.name}: #{e.message}")
          Rails.logger.error("  Record: #{record.inspect}")
          Rails.logger.error("  Errors: #{record.errors.full_messages}")
          raise
        end
        apply_timestamps!(record, source_created_at, source_updated_at)
      end
    end

    def find_existing_child(association:, attrs:)
      case association.klass.name
      when "Creator", "Contributor", "Funder"
        association.find_by(name: attrs[:name], position: attrs[:position])
      when "RelatedMaterial"
        association.find_by(title: attrs[:title], relation_type: attrs[:relation_type], uri: attrs[:uri])
      when "Datafile"
        key = attrs[:web_id].presence || attrs[:binary_name]
        attrs[:web_id].present? ? association.find_by(web_id: key) : association.find_by(binary_name: key)
      when "Note"
        association.find_by(author: attrs[:author], body: attrs[:body])
      end
    end

    def normalized_creators
      Array(payload["creators"]).each_with_index.filter_map do |creator, index|
        name_fields = normalized_name_fields(
          given_name: creator["given_name"],
          family_name: creator["family_name"],
          institution_name: creator["institution_name"],
          legacy_name: creator["name"]
        )
        next if name_fields[:name].blank?

        {
          name: name_fields[:name],
          institution_name: name_fields[:institution_name],
          given_name: name_fields[:given_name],
          family_name: name_fields[:family_name],
          email: creator["email"],
          identifier: creator["identifier"],
          identifier_scheme: creator["identifier_scheme"],
          contact: !!creator["is_contact"],
          position: (creator["row_position"] || (index + 1)).to_i,
          source_created_at: creator["created_at"],
          source_updated_at: creator["updated_at"]
        }
      end
    end

    def normalized_contributors
      Array(payload["contributors"]).each_with_index.filter_map do |contributor, index|
        name_fields = normalized_name_fields(
          given_name: contributor["given_name"],
          family_name: contributor["family_name"],
          institution_name: contributor["institution_name"],
          legacy_name: contributor["name"]
        )
        next if name_fields[:name].blank?

        {
          name: name_fields[:name],
          institution_name: name_fields[:institution_name],
          given_name: name_fields[:given_name],
          family_name: name_fields[:family_name],
          email: contributor["email"],
          identifier: contributor["identifier"],
          identifier_scheme: contributor["identifier_scheme"],
          role: contributor["role"],
          position: (contributor["row_position"] || contributor["position"] || (index + 1)).to_i,
          source_created_at: contributor["created_at"],
          source_updated_at: contributor["updated_at"]
        }
      end
    end

    def normalized_funders
      Array(payload["funders"]).each_with_index.filter_map do |funder, index|
        name = funder["name"].to_s.strip
        next if name.blank?

        {
          name: name,
          identifier: funder["identifier"],
          award_number: funder["grant"].presence || funder["award_number"],
          position: (funder["row_position"] || funder["position"] || (index + 1)).to_i,
          source_created_at: funder["created_at"],
          source_updated_at: funder["updated_at"]
        }
      end
    end

    def normalized_related_materials
      Array(payload["related_materials"]).each_with_index.filter_map do |material, index|
        title = material["citation"].to_s.strip
        title = material["title"].to_s.strip if title.blank?
        title = material["link"].to_s.strip if title.blank?
        title = material["uri"].to_s.strip if title.blank?
        title = material["material_type"].to_s.strip if title.blank?
        next if title.blank?

        uri = normalized_material_uri(material)
        relation_types = normalized_relation_types(material: material, uri: uri)

        {
          title: title,
          material_type: material["material_type"],
          selected_type: material["selected_type"],
          availability: material["availability"],
          link: material["link"],
          uri_type: material["uri_type"],
          citation: material["citation"],
          note: material["note"],
          relation_type: relation_types.first,
          datacite_list: relation_types.join(","),
          uri: uri,
          position: (material["row_position"] || material["position"] || (index + 1)).to_i,
          source_created_at: material["created_at"],
          source_updated_at: material["updated_at"]
        }
      end
    end

    def normalized_datafiles
      Array(datafiles_payload).filter_map do |datafile|
        # Keep canonical listing terminology for archive previews.
        peek_type = datafile["peek_type"]
        peek_type = Datafile::PeekType::LISTING if peek_type == Datafile::PeekType::LISTING

        {
          web_id: datafile["web_id"].presence,
          medusa_id: datafile["medusa_id"],
          binary_name: datafile["binary_name"],
          binary_size: datafile["binary_size"],
          storage_root: datafile["storage_root"],
          storage_key: datafile["storage_key"],
          description: datafile["description"],
          peek_type: peek_type,
          peek_content: datafile["peek_text"],
          source_created_at: datafile["created_at"],
          source_updated_at: datafile["updated_at"],
          nested_items: datafile["nested_items"]
        }
      end
    end

    def datafiles_payload
      return payload["datafiles"] if payload.respond_to?(:key?) && payload.key?("datafiles")
      return payload[:datafiles] if payload.respond_to?(:key?) && payload.key?(:datafiles)

      nil
    end

    def datafiles_payload_provided?
      !datafiles_payload.nil?
    end

    def normalized_notes
      Array(payload["notes"]).filter_map do |note|
        body = note["body"]
        author = note["author"]
        next if body.blank? && author.blank?

        {
          body: body,
          author: author,
          source_created_at: note["created_at"],
          source_updated_at: note["updated_at"]
        }
      end
    end

    def normalized_token
      token_payload = payload["token"]
      return nil unless token_payload.is_a?(Hash)

      identifier = token_payload["identifier"].to_s.strip
      return nil if identifier.blank?

      {
        identifier: identifier,
        expires: parse_time(token_payload["expires"]),
        source_created_at: token_payload["created_at"],
        source_updated_at: token_payload["updated_at"]
      }
    end

    def sync_token!(dataset)
      token_attrs = normalized_token
      return if token_attrs.nil?

      source_created_at = token_attrs.delete(:source_created_at)
      source_updated_at = token_attrs.delete(:source_updated_at)

      token = dataset.token || dataset.build_token(dataset_key: dataset.key)
      token.assign_attributes(token_attrs)
      token.save!
      apply_timestamps!(token, source_created_at, source_updated_at)
    end

    def normalized_material_uri(material)
      candidates = [ material["uri"], material["link"] ]
      candidates.each do |value|
        normalized = normalize_http_uri(value)
        return normalized if normalized.present?
      end
      nil
    end

    def normalized_relation_types(material:, uri:)
      candidates = []
      candidates.concat(Array(material["relation_types"]))
      candidates.concat(material["datacite_list"].to_s.split(","))
      candidates << material["relation_type"]
      candidates << material["material_type"]

      normalized = candidates
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
        .select { |value| RelatedMaterial::RELATION_TYPE_OPTIONS.include?(value) }
        .uniq

      # Legacy payloads may include URI without explicit relationship metadata.
      return [ "IsSupplementTo" ] if normalized.empty? && uri.present?

      normalized
    end

    def normalize_http_uri(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      uri = URI.parse(raw)
      return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def combine_name(given_name:, family_name:, fallback_name:)
      given = given_name.to_s.strip
      family = family_name.to_s.strip
      combined = [ given, family ].reject(&:blank?).join(" ").strip
      return combined if combined.present?

      fallback_name.to_s.strip
    end

    def normalized_name_fields(given_name:, family_name:, institution_name:, legacy_name:)
      normalized_given_name = given_name.to_s.strip.presence
      normalized_family_name = family_name.to_s.strip.presence

      normalized_institution_name = institution_name.to_s.strip.presence
      if normalized_institution_name.blank? && normalized_given_name.blank? && normalized_family_name.blank?
        normalized_institution_name = legacy_name.to_s.strip.presence
      end

      canonical_name = combine_name(
        given_name: normalized_given_name,
        family_name: normalized_family_name,
        fallback_name: normalized_institution_name
      )

      {
        name: canonical_name,
        institution_name: normalized_institution_name,
        given_name: normalized_given_name,
        family_name: normalized_family_name
      }
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      return nil if value.blank?

      parsed_time = parse_time(value)
      return parsed_time.to_date if parsed_time

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def apply_timestamps!(record, created_at_value, updated_at_value)
      created_at = parse_time(created_at_value)
      updated_at = parse_time(updated_at_value)
      return unless created_at || updated_at

      values = {}
      values[:created_at] = created_at if created_at
      values[:updated_at] = updated_at if updated_at
      record.update_columns(values)
    end

    def dataset_key
      return payload["key"] if payload["key"].present?

      from_url = payload["url"].to_s[/\/datasets\/([^\/]+)\.json\z/i, 1]
      return from_url if from_url.present?

      nil
    end
  end
end
