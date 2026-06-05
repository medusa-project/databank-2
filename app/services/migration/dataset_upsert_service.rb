require "uri"

module Migration
  class DatasetUpsertService
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

      return dry_run_result(existing, key, identifier) if dry_run

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

    def dry_run_result(existing, key, identifier)
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
      dataset.title = payload["title"].presence || "Untitled Dataset"
      dataset.description = payload["description"]
      dataset.identifier = payload["identifier"].presence
      dataset.publisher = payload["publisher"]
      dataset.license = payload["license"]
      dataset.keywords = payload["keywords"]
      dataset.subject = payload["subject"]
      dataset.publication_state = publication_state_value(payload["publication_state"])
      dataset.published_at = parse_time(payload["release_date"]) || parse_time(payload["updated_at"])

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

    def publication_state_value(raw)
      value = raw.to_s.downcase
      return :published if %w[published released].include?(value)

      :draft
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

      sync_collection!(dataset.datafiles, normalized_datafiles) do |record, attrs|
        record.assign_attributes(attrs)
      end

      sync_collection!(dataset.notes, normalized_notes) do |record, attrs|
        record.assign_attributes(attrs)
      end
    end

    def sync_collection!(association, rows)
      association.delete_all if overwrite
      return if rows.empty?

      rows.each do |attrs|
        row = attrs.dup
        source_created_at = row.delete(:source_created_at)
        source_updated_at = row.delete(:source_updated_at)

        record = find_existing_child(association, row)
        record ||= association.build
        yield(record, row)
        record.save!
        apply_timestamps!(record, source_created_at, source_updated_at)
      end
    end

    def find_existing_child(association, attrs)
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
        name = combine_name(creator["given_name"], creator["family_name"], creator["name"])
        next if name.blank?

        {
          name: name,
          email: creator["email"],
          contact: !!creator["is_contact"],
          position: (creator["row_position"] || (index + 1)).to_i,
          source_created_at: creator["created_at"],
          source_updated_at: creator["updated_at"]
        }
      end
    end

    def normalized_contributors
      Array(payload["contributors"]).each_with_index.filter_map do |contributor, index|
        name = combine_name(contributor["given_name"], contributor["family_name"], contributor["name"])
        next if name.blank?

        {
          name: name,
          email: contributor["email"],
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

        {
          title: title,
          relation_type: normalized_relation_type(material, uri),
          uri: uri,
          position: (material["row_position"] || material["position"] || (index + 1)).to_i,
          source_created_at: material["created_at"],
          source_updated_at: material["updated_at"]
        }
      end
    end

    def normalized_datafiles
      Array(payload["datafiles"]).filter_map do |datafile|
        {
          web_id: datafile["web_id"].presence,
          medusa_id: datafile["medusa_id"],
          binary_name: datafile["binary_name"],
          binary_size: datafile["binary_size"],
          storage_root: datafile["storage_root"],
          storage_key: datafile["storage_key"],
          description: datafile["description"],
          source_created_at: datafile["created_at"],
          source_updated_at: datafile["updated_at"]
        }
      end
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

    def normalized_relation_type(material, uri)
      candidate = material["relation_type"].presence || material["material_type"].presence
      return candidate if RelatedMaterial::RELATION_TYPE_OPTIONS.include?(candidate)

      # Legacy sample payloads often use material_type values like "Article".
      # For URI-linked entries, default to a supported relationship type.
      return "IsSupplementTo" if uri.present?

      nil
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

    def combine_name(given_name, family_name, fallback_name)
      given = given_name.to_s.strip
      family = family_name.to_s.strip
      combined = [ given, family ].reject(&:blank?).join(" ").strip
      return combined if combined.present?

      fallback_name.to_s.strip
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
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
