require "json"
require "digest"
require "fileutils"

module Migration
  class FlatBundleImportService
    DEFAULT_BATCH_SIZE = 100
    BATCH_SIZE_ENV = "FLAT_BUNDLE_IMPORT_BATCH_SIZE"
    BATCH_PAUSE_ENV = "FLAT_BUNDLE_IMPORT_BATCH_PAUSE_SECONDS"
    CHECKPOINT_EVERY_ENV = "FLAT_BUNDLE_IMPORT_CHECKPOINT_EVERY"
    CHECKPOINT_FILE_ENV = "FLAT_BUNDLE_IMPORT_CHECKPOINT_FILE"
    RESUME_FROM_LINE_ENV = "FLAT_BUNDLE_IMPORT_RESUME_FROM_LINE"
    MAX_RECORDS_ENV = "FLAT_BUNDLE_IMPORT_MAX_RECORDS"
    DEFAULT_CHECKPOINT_EVERY = 5_000

    attr_reader :bundle_path, :overwrite, :dry_run, :checksum_path, :manifest_path, :report_path

    def initialize(bundle_path:, overwrite: false, dry_run: false, checksum_path: nil, manifest_path: nil, report_path: nil)
      @bundle_path = Pathname(bundle_path)
      @overwrite = overwrite
      @dry_run = dry_run
      @checksum_path = checksum_path.present? ? Pathname(checksum_path) : nil
      @manifest_path = manifest_path.present? ? Pathname(manifest_path) : nil
      @report_path = resolve_report_path(report_path)
      @normalized_datafile_ids = {}
      @batch_size = configured_batch_size
      @batch_pause_seconds = configured_batch_pause_seconds
      @checkpoint_every = configured_checkpoint_every
      @checkpoint_path = configured_checkpoint_path
      @resume_from_line = configured_resume_from_line
      @max_records = configured_max_records
    end

    def call
      summary = {
        bundle_path: bundle_path.to_s,
        resume_from_line: resume_from_line,
        max_records: max_records,
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
      last_source_line = nil
      stopped_early = false
      start_time = Time.current

      # Batch processing
      batches = { datasets: [], datafiles: [], nested_items: [] }
      dataset_map = {} # Track created datasets for relationships

      if batch_size != DEFAULT_BATCH_SIZE || batch_pause_seconds.positive?
        puts "Flat import config: batch_size=#{batch_size}, batch_pause_seconds=#{batch_pause_seconds}"
      end
      if resume_from_line > 1 || max_records.present?
        puts "Flat import window: resume_from_line=#{resume_from_line}, max_records=#{max_records || 'all'}"
      end

      File.foreach(bundle_path).with_index(1) do |line, line_number|
        next if line.strip.empty?
        next if line_number < resume_from_line
        if max_records.present? && processed_count >= max_records
          stopped_early = true
          break
        end

        begin
          record = JSON.parse(line)
          record_type = record.delete("type")
          record["_source_line"] = line_number

          case record_type
          when "dataset"
            batches[:datasets] << record
            if batches[:datasets].size >= batch_size
              flush_datasets_batch(batches[:datasets], dataset_map, summary, dry_run)
              batches[:datasets] = []
              pause_between_batches!
            end

          when "datafile"
            batches[:datafiles] << record
            if batches[:datafiles].size >= batch_size
              flush_datafiles_batch(batches[:datafiles], summary, dry_run)
              batches[:datafiles] = []
              pause_between_batches!
            end

          when "nested_item"
            batches[:nested_items] << record
          end

          processed_count += 1
          last_source_line = line_number

          # Progress every 500 records
          if processed_count % 500 == 0
            elapsed = (Time.current - start_time).to_i
            puts "[#{processed_count}] records processed (#{elapsed}s)"
          end

          write_checkpoint_artifact!(summary: summary, processed_count: processed_count, last_source_line: last_source_line, stopped_early: stopped_early) if checkpoint_every.positive? && (processed_count % checkpoint_every).zero?
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
      if batches[:datasets].any?
        flush_datasets_batch(batches[:datasets], dataset_map, summary, dry_run)
        pause_between_batches!
      end

      if batches[:datafiles].any?
        flush_datafiles_batch(batches[:datafiles], summary, dry_run)
        pause_between_batches!
      end

      # Nested items depend on datafiles, so process these only after all datafiles are created.
      batches[:nested_items].each_slice(batch_size) do |slice|
        flush_nested_items_batch(slice, summary, dry_run)
        pause_between_batches!
      end

      summary[:processed_count] = processed_count
      summary[:last_source_line] = last_source_line
      summary[:stopped_early] = stopped_early
      summary[:next_resume_from_line] = last_source_line.present? ? last_source_line + 1 : resume_from_line
      summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_counts", "datasets") }
      summary[:checksum] = safe_expected_checksum
      write_report_artifact!(summary)
      write_checkpoint_artifact!(summary: summary, processed_count: processed_count, last_source_line: last_source_line, stopped_early: stopped_early)

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
      summary[:last_source_line] = last_source_line if defined?(last_source_line) && defined?(summary)
      summary[:stopped_early] = stopped_early if defined?(stopped_early) && defined?(summary)
      if defined?(summary)
        summary[:next_resume_from_line] = if defined?(last_source_line) && last_source_line.present?
          last_source_line + 1
        else
          resume_from_line
        end
      end
      summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_counts", "datasets") } if defined?(summary)
      summary[:checksum] = safe_expected_checksum if defined?(summary)
      write_report_artifact!(summary) if defined?(summary)
      write_checkpoint_artifact!(summary: summary, processed_count: processed_count || 0, last_source_line: defined?(last_source_line) ? last_source_line : nil, stopped_early: defined?(stopped_early) ? stopped_early : false) if defined?(summary)
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

  attr_reader :batch_size, :batch_pause_seconds, :checkpoint_every, :checkpoint_path, :resume_from_line, :max_records

    def configured_batch_size
      raw = ENV[BATCH_SIZE_ENV]
      parsed = Integer(raw, exception: false)
      return DEFAULT_BATCH_SIZE if parsed.nil? || parsed <= 0

      parsed
    end

    def configured_batch_pause_seconds
      raw = ENV[BATCH_PAUSE_ENV]
      return 0.0 if raw.blank?

      parsed = Float(raw, exception: false)
      return 0.0 if parsed.nil? || parsed.negative?

      parsed
    end

    def pause_between_batches!
      return unless batch_pause_seconds.positive?

      sleep(batch_pause_seconds)
    end

    def configured_checkpoint_every
      raw = ENV[CHECKPOINT_EVERY_ENV]
      parsed = Integer(raw, exception: false)
      return DEFAULT_CHECKPOINT_EVERY if parsed.nil? || parsed <= 0

      parsed
    end

    def configured_checkpoint_path
      raw = ENV[CHECKPOINT_FILE_ENV]
      return report_path.sub_ext(".checkpoint.json") if raw.blank?

      path = Pathname(raw)
      path.absolute? ? path : bundle_path.dirname.join(path)
    end

    def configured_resume_from_line
      raw = ENV[RESUME_FROM_LINE_ENV]
      parsed = Integer(raw, exception: false)
      return 1 if parsed.nil? || parsed <= 0

      parsed
    end

    def configured_max_records
      raw = ENV[MAX_RECORDS_ENV]
      parsed = Integer(raw, exception: false)
      return nil if parsed.nil? || parsed <= 0

      parsed
    end

    def flush_datasets_batch(records, dataset_map, summary, dry_run)
      return if records.empty?

      if dry_run
        summary[:record_counts][:datasets] += records.size
        return
      end

      records.each do |record|
        begin
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
        rescue StandardError => e
          summary[:failed] += 1
          summary[:records] << {
            line: record["_source_line"],
            status: :failed,
            message: e.message
          }
        end
      end
    end

    def flush_datafiles_batch(records, summary, dry_run)
      return if records.empty?

      if dry_run
        summary[:record_counts][:datafiles] += records.size
        return
      end

      dataset_keys = records.map { |record| record["dataset_id"] }.compact.uniq
      datasets_by_key = Dataset.where(key: dataset_keys).index_by(&:key)

      records.each do |record|
        dataset_key = record["dataset_id"]
        dataset = datasets_by_key[dataset_key]
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

      dataset_keys = records.map { |record| record["dataset_id"] }.compact.uniq
      datasets_by_key = Dataset.where(key: dataset_keys).index_by(&:key)

      datafile_lookup_pairs = records.filter_map do |record|
        dataset = datasets_by_key[record["dataset_id"]]
        next unless dataset

        web_id = normalized_datafile_web_id(dataset_key: record["dataset_id"], source_id: record["datafile_id"])
        [ dataset.id, web_id ]
      end.uniq

      datafile_ids_by_lookup = if datafile_lookup_pairs.any?
        scope = Datafile.where(dataset_id: datafile_lookup_pairs.map(&:first).uniq, web_id: datafile_lookup_pairs.map(&:last).uniq)
        scope.each_with_object({}) do |datafile, acc|
          acc[[ datafile.dataset_id, datafile.web_id ]] = datafile.id
        end
      else
        {}
      end

      NestedItem.transaction do
        records.each do |record|
          dataset = datasets_by_key[record["dataset_id"]]
          next unless dataset

          web_id = normalized_datafile_web_id(dataset_key: record["dataset_id"], source_id: record["datafile_id"])
          datafile_id = datafile_ids_by_lookup[[ dataset.id, web_id ]]
          next unless datafile_id

          # Parse item_id to get database ID (format: "ni-123")
          db_id = record["item_id"].sub(/^ni-/, "").to_i

          # Parse parent_item_id if present
          parent_db_id = nil
          if record["parent_item_id"].present?
            parent_db_id = record["parent_item_id"].sub(/^ni-/, "").to_i
          end

          nested_item = NestedItem.find_or_create_by(
            id: db_id,
            datafile_id: datafile_id,
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

    def write_checkpoint_artifact!(summary:, processed_count:, last_source_line:, stopped_early:)
      payload = {
        generated_at: Time.current.iso8601,
        bundle_path: bundle_path.to_s,
        report_path: report_path.to_s,
        checkpoint_every: checkpoint_every,
        resume_from_line: resume_from_line,
        max_records: max_records,
        processed_count: processed_count,
        last_source_line: last_source_line,
        next_resume_from_line: last_source_line.present? ? last_source_line + 1 : resume_from_line,
        stopped_early: stopped_early,
        summary: {
          created: summary[:created],
          updated: summary[:updated],
          skipped_existing: summary[:skipped_existing],
          failed: summary[:failed],
          datasets: summary.dig(:record_counts, :datasets),
          datafiles: summary.dig(:record_counts, :datafiles),
          nested_items: summary.dig(:record_counts, :nested_items),
          validation_error: summary[:validation_error]
        }
      }

      temp_path = Pathname("#{checkpoint_path}.tmp")
      File.write(temp_path, JSON.pretty_generate(payload))
      FileUtils.mv(temp_path, checkpoint_path)
    end
  end
end
