require "json"
require "digest"

module Migration
  class FlatBundleImportService
    attr_reader :bundle_path, :overwrite, :dry_run, :checksum_path, :manifest_path, :report_path

    def initialize(bundle_path:, overwrite: false, dry_run: false, checksum_path: nil, manifest_path: nil, report_path: nil)
      @bundle_path = Pathname(bundle_path)
      @overwrite = overwrite
      @dry_run = dry_run
      @checksum_path = checksum_path.present? ? Pathname(checksum_path) : nil
      @manifest_path = manifest_path.present? ? Pathname(manifest_path) : nil
      @report_path = resolve_report_path(report_path)
      @normalized_datafile_ids = {}
    end

    def call
      summary = {
        bundle_path: bundle_path.to_s,
        created: 0,
        updated: 0,
        skipped_existing: 0,
        would_create: 0,
        would_update: 0,
        failed: 0,
        validation_error: nil,
        records: [],
        record_counts: {
          datasets: 0,
          datafiles: 0,
          nested_items: 0
        }
      }

      validate_paths!
      verify_bundle_integrity!

      processed_count = 0
      start_time = Time.current

      # Batch processing
      batches = { datasets: [], datafiles: [], nested_items: [] }
      batch_size = 100
      dataset_map = {} # Track created datasets for relationships

      File.foreach(bundle_path).with_index(1) do |line, line_number|
        next if line.strip.empty?

        begin
          record = JSON.parse(line)
          record_type = record.delete("type")

          case record_type
          when "dataset"
            batches[:datasets] << record
            if batches[:datasets].size >= batch_size
              flush_datasets_batch(batches[:datasets], dataset_map, summary, dry_run)
              batches[:datasets] = []
            end

          when "datafile"
            batches[:datafiles] << record
            if batches[:datafiles].size >= batch_size
              flush_datafiles_batch(batches[:datafiles], summary, dry_run)
              batches[:datafiles] = []
            end

          when "nested_item"
            batches[:nested_items] << record
          end

          processed_count += 1

          # Progress every 500 records
          if processed_count % 500 == 0
            elapsed = (Time.current - start_time).to_i
            puts "[#{processed_count}] records processed (#{elapsed}s)"
          end
        rescue StandardError => e
          summary[:failed] += 1
          summary[:records] << {
            line: line_number,
            status: :failed,
            message: e.message
          }
        end
      end

      # Flush remaining batches
      flush_datasets_batch(batches[:datasets], dataset_map, summary, dry_run) if batches[:datasets].any?
      flush_datafiles_batch(batches[:datafiles], summary, dry_run) if batches[:datafiles].any?

      # Nested items depend on datafiles, so process these only after all datafiles are created.
      batches[:nested_items].each_slice(batch_size) do |slice|
        flush_nested_items_batch(slice, summary, dry_run)
      end

      summary[:processed_count] = processed_count
      summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_counts", "datasets") }
      summary[:checksum] = safe_expected_checksum
      write_report_artifact!(summary)

      total_time = (Time.current - start_time).to_i
      puts "Import complete: #{processed_count} records processed in #{total_time}s"
      puts "  Datasets: #{summary[:record_counts][:datasets]}"
      puts "  Datafiles: #{summary[:record_counts][:datafiles]}"
      puts "  Nested items: #{summary[:record_counts][:nested_items]}"

      summary
    rescue StandardError => e
      summary[:validation_error] = e.message if defined?(summary)
      summary[:failed] += 1 if defined?(summary)
      summary[:processed_count] = processed_count if defined?(processed_count) && defined?(summary)
      summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_counts", "datasets") } if defined?(summary)
      summary[:checksum] = safe_expected_checksum if defined?(summary)
      write_report_artifact!(summary) if defined?(summary)
      summary || {
        bundle_path: bundle_path.to_s,
        created: 0,
        updated: 0,
        skipped_existing: 0,
        would_create: 0,
        would_update: 0,
        failed: 1,
        validation_error: e.message,
        processed_count: processed_count || 0
      }
    end

    private

    def flush_datasets_batch(records, dataset_map, summary, dry_run)
      return if records.empty?

      if dry_run
        summary[:record_counts][:datasets] += records.size
        return
      end

      records.each do |record|
        dataset_id = record["dataset_id"]

        existing = Dataset.find_by(key: dataset_id)

        if existing && !overwrite
          summary[:skipped_existing] += 1
          dataset_map[dataset_id] = existing
          next
        end

        dataset = existing || Dataset.new(key: dataset_id)

        normalized_publication_state = normalize_publication_state(record["publication_state"])

        # Assign attributes from flat record
        attributes = {
          title: record["title"],
          identifier: normalize_identifier(record["identifier"]),
          publisher: record["publisher"],
          publication_year: record["publication_year"],
          description: record["description"],
          license: record["license"],
          owner_uid: record["owner_uid"],
          corresponding_creator_name: record["corresponding_creator_name"],
          depositor_name: record["depositor_name"],
          depositor_email: record["depositor_email"],
          subject: record["subject"],
          keywords: record["keywords"],
          hold_state: record["hold_state"],
          release_date: record["release_date"],
          embargo: normalize_embargo(record["embargo"]),
          is_test: boolean_or_false(record["is_test"]),
          is_import: boolean_or_false(record["is_import"]),
          tombstone_date: record["tombstone_date"],
          dataset_version: record["dataset_version"],
          nested_updated_at: record["nested_updated_at"]
        }
        attributes[:publication_state] = normalized_publication_state if normalized_publication_state.present?
        dataset.assign_attributes(assignable_attributes(dataset, attributes))

        dataset.save!

        # Sync nested records from flat format after the dataset exists
        sync_flat_collections!(dataset, record)
        dataset_map[dataset_id] = dataset

        if existing
          summary[:updated] += 1
        else
          summary[:created] += 1
        end

        summary[:record_counts][:datasets] += 1
      end
    end

    def flush_datafiles_batch(records, summary, dry_run)
      return if records.empty?

      if dry_run
        summary[:record_counts][:datafiles] += records.size
        return
      end

      records.each do |record|
        dataset_key = record["dataset_id"]
        dataset = Dataset.find_by(key: dataset_key)
        next unless dataset

        web_id = normalized_datafile_web_id(dataset_key: dataset_key, source_id: record["datafile_id"])
        datafile = dataset.datafiles.find_or_create_by(web_id: web_id)

        datafile_attributes = {
          binary_name: record["binary_name"],
          binary_size: record["binary_size"],
          medusa_id: record["medusa_id"],
          storage_root: record["storage_root"],
          storage_key: record["storage_key"],
          description: record["description"],
          peek_type: normalize_datafile_peek_type(record["peek_type"]),
          peek_content: record["peek_text"]
        }

        datafile.assign_attributes(assignable_attributes(datafile, datafile_attributes))

        datafile.save!
        summary[:record_counts][:datafiles] += 1
      end
    end

    def flush_nested_items_batch(records, summary, dry_run)
      return if records.empty?

      if dry_run
        summary[:record_counts][:nested_items] += records.size
        return
      end

      # Group by datafile for efficient processing
      by_datafile = records.group_by { |r| "#{r['dataset_id']}:#{r['datafile_id']}" }

      NestedItem.transaction do
        by_datafile.each do |_key, items|
          items.each do |record|
            dataset = Dataset.find_by(key: record["dataset_id"])
            web_id = normalized_datafile_web_id(dataset_key: record["dataset_id"], source_id: record["datafile_id"])
            datafile = dataset&.datafiles&.find_by(web_id: web_id)
            next unless datafile

            # Parse item_id to get database ID (format: "ni-123")
            db_id = record["item_id"].sub(/^ni-/, "").to_i

            # Parse parent_item_id if present
            parent_db_id = nil
            if record["parent_item_id"].present?
              parent_db_id = record["parent_item_id"].sub(/^ni-/, "").to_i
            end

            nested_item = NestedItem.find_or_create_by(
              id: db_id,
              datafile_id: datafile.id,
              item_name: record["item_name"]
            ) do |item|
              item.parent_id = parent_db_id
            end

            # Update attributes if needed
            if nested_item.media_type != record["media_type"] ||
               nested_item.size != record["size"] ||
               nested_item.item_path != record["item_path"] ||
               nested_item.is_directory != record["is_directory"]

              nested_item.update!(
                parent_id: parent_db_id,
                media_type: record["media_type"],
                size: record["size"],
                item_path: record["item_path"],
                is_directory: record["is_directory"]
              )
            end

            summary[:record_counts][:nested_items] += 1
          end
        end
      end
    end

    def sync_flat_collections!(dataset, dataset_record)
      # Sync creators
      sync_creators_contributors!(dataset.creators, dataset_record["creators"]) if dataset_record["creators"].present?

      # Sync contributors
      sync_creators_contributors!(dataset.contributors, dataset_record["contributors"]) if dataset_record["contributors"].present?

      # Sync funders
      sync_funders!(dataset.funders, dataset_record["funders"]) if dataset_record["funders"].present?

      # Sync related materials
      if dataset_record["related_materials"].present?
        dataset.related_materials.reorder(:id).destroy_all if overwrite

        dataset_record["related_materials"].each_with_index do |attrs, idx|
          position = idx + 1
          title = attrs["title"].presence || attrs["citation"].presence || attrs["link"].presence || attrs["uri"].presence || "material"
          material = dataset.related_materials.find_or_create_by(title: title)
          material.update!(
            citation: attrs["citation"],
            link: attrs["link"],
            uri: attrs["uri"],
            uri_type: attrs["uri_type"],
            material_type: attrs["material_type"],
            selected_type: attrs["selected_type"],
            availability: attrs["availability"],
            note: attrs["note"],
            datacite_list: attrs["datacite_list"],
            position: position,
            row_position: position
          )
        end
      end

      # Sync notes
      if dataset_record["notes"].present?
        dataset.notes.reorder(:id).destroy_all if overwrite

        dataset_record["notes"].each do |attrs|
          dataset.notes.find_or_create_by(
            author: attrs["author"],
            body: attrs["body"]
          )
        end
      end

      # Sync token
      if dataset_record["token"].present?
        token_data = dataset_record["token"]
        token = Token.find_or_create_by(dataset_key: dataset.key)
        token.update!(
          identifier: token_data["identifier"],
          expires: token_data["expires"]
        )
      end
    end

    def sync_creators_contributors!(association, people_data)
      association.reorder(:id).destroy_all if overwrite

      people_data.each_with_index do |attrs, idx|
        position = normalized_position(attrs["row_position"], idx)
        name = attrs["name"].presence ||
               attrs["institution_name"].presence ||
               [ attrs["given_name"], attrs["family_name"] ].compact.join(" ").strip.presence ||
               attrs["email"]
        next if name.blank?

        person = association.find_or_create_by(
          family_name: attrs["family_name"],
          given_name: attrs["given_name"],
          institution_name: attrs["institution_name"]
        ) { |p| p.name = name }

        person.update!(
          name: name,
          family_name: attrs["family_name"],
          given_name: attrs["given_name"],
          institution_name: attrs["institution_name"],
          email: attrs["email"],
          identifier: attrs["identifier"],
          identifier_scheme: attrs["identifier_scheme"],
          is_contact: attrs["is_contact"] || false,
          row_position: position,
          position: position
        )
      end
    end

    def sync_funders!(association, funders_data)
      association.reorder(:id).destroy_all if overwrite

      funders_data.each_with_index do |attrs, idx|
        position = normalized_position(attrs["row_position"], idx)
        next if attrs["name"].blank?

        funder = association.find_or_create_by(name: attrs["name"])
        funder.update!(
          identifier: attrs["identifier"],
          identifier_scheme: attrs["identifier_scheme"],
          grant: attrs["grant"],
          position: position,
          row_position: position
        )
      end
    end

    def normalized_position(raw_position, index)
      position = raw_position.to_i
      return position if position.positive?

      index + 1
    end

    def normalize_publication_state(value)
      normalized = value.to_s.strip.downcase
      return if normalized.blank?
      return normalized if %w[draft published].include?(normalized)
      return "published" if normalized == "released"

      nil
    end

    def normalize_identifier(value)
      normalized = value.to_s.strip
      normalized.presence
    end

    def normalize_embargo(value)
      normalized = value.to_s.strip.downcase
      return "none" if normalized.blank? || normalized == "none"
      return "file" if [ "file", "file embargo" ].include?(normalized)
      return "metadata" if [ "metadata", "metadata embargo" ].include?(normalized)

      normalized
    end

    def normalize_datafile_peek_type(value)
      normalized = value.to_s.strip.downcase
      return Datafile::PeekType::LISTING if normalized == Datafile::PeekType::LISTING
      return Datafile::PeekType::NONE if normalized == Datafile::PeekType::NONE

      normalized.presence
    end

    def normalized_datafile_web_id(dataset_key:, source_id:)
      raw_value = source_id.to_s.strip
      downcased_value = raw_value.downcase

      if downcased_value.match?(web_id_format_regex)
        existing = Datafile.find_by(web_id: downcased_value)
        return downcased_value if existing.blank? || existing.dataset&.key == dataset_key
      end

      cache_key = "#{dataset_key}:#{raw_value}"
      return @normalized_datafile_ids[cache_key] if @normalized_datafile_ids.key?(cache_key)

      attempt = 0
      begin
        seed = attempt.zero? ? cache_key : "#{cache_key}:#{attempt}"
        candidate = deterministic_web_id(seed)
        existing = Datafile.find_by(web_id: candidate)
        attempt += 1
      end while existing.present? && existing.dataset&.key != dataset_key

      @normalized_datafile_ids[cache_key] = candidate
    end

    def web_id_format_regex
      /\A[a-z0-9]{#{Datafile::WEB_ID_LENGTH}}\z/
    end

    def deterministic_web_id(seed)
      base36 = Digest::SHA256.hexdigest(seed.to_s)[0, 12].to_i(16).to_s(36)
      base36.rjust(Datafile::WEB_ID_LENGTH, "0")[-Datafile::WEB_ID_LENGTH, Datafile::WEB_ID_LENGTH]
    end

    def boolean_or_false(value)
      cast = ActiveModel::Type::Boolean.new.cast(value)
      cast.nil? ? false : cast
    end

    def assignable_attributes(record, attributes)
      attributes.select { |key, _value| record.has_attribute?(key) }
    end

    def validate_paths!
      raise ArgumentError, "bundle not found: #{bundle_path}" unless bundle_path.file?
      raise ArgumentError, "checksum file not found: #{checksum_path}" if checksum_path.present? && !File.file?(checksum_path)
      raise ArgumentError, "manifest file not found: #{manifest_path}" if manifest_path.present? && !File.file?(manifest_path)
    end

    def verify_bundle_integrity!
      manifest_data = manifest_path.present? ? JSON.parse(File.read(manifest_path)) : nil
      expected_checksum = manifest_data&.dig("sha256").to_s.strip.presence

      if expected_checksum.blank? && checksum_path.present?
        expected_checksum = File.read(checksum_path).strip.split.first.to_s.strip.presence
      end

      if expected_checksum.present?
        actual_checksum = Digest::SHA256.file(bundle_path).hexdigest
        raise ArgumentError, "bundle checksum mismatch" unless actual_checksum == expected_checksum
      end
    end

    def manifest_data
      @manifest_data ||= manifest_path.present? ? JSON.parse(File.read(manifest_path)) : nil
    end

    def safe_manifest_value
      yield
    rescue StandardError
      nil
    end

    def safe_expected_checksum
      return nil unless checksum_path.present?
      File.read(checksum_path).strip.split.first.to_s.strip.presence
    end

    def resolve_report_path(report_override)
      return Pathname(report_override) if report_override.present? && Pathname(report_override).absolute?
      bundle_path.dirname.join("cutover_flat_datasets_report.json")
    end

    def write_report_artifact!(summary)
      File.write(report_path, JSON.pretty_generate(summary))
    end
  end
end
