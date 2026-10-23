module Globus
  class IngestImportService
    def initialize(dataset_key: nil, dry_run: false, dataset_limit: nil, logger: Rails.logger)
      @dataset_key = dataset_key.to_s.strip.presence
      @dry_run = dry_run
      @dataset_limit = dataset_limit.to_i.positive? ? dataset_limit.to_i : nil
      @logger = logger
    end

    def call
      summary = {
        dry_run: @dry_run,
        dataset_key: @dataset_key,
        dataset_limit: @dataset_limit,
        datasets_scanned: 0,
        records_scanned: 0,
        created: 0,
        skipped_existing: 0,
        skipped_invalid: 0,
        failed: 0,
        records: []
      }

      datasets_scope.each do |dataset|
        break if @dataset_limit && summary[:datasets_scanned] >= @dataset_limit

        summary[:datasets_scanned] += 1
        dataset.with_lock { import_dataset(dataset: dataset, summary: summary) }
      end

      summary
    end

    private

    def datasets_scope
      scope = Dataset.order(:id)
      @dataset_key.present? ? scope.where(key: @dataset_key) : scope
    end

    def import_dataset(dataset:, summary:)
      ingest_root = StorageManager.instance.globus_ingest_root
      directory_exists = ingest_root.exist?("#{dataset.key}/")
      unless directory_exists || ingest_root.root_type == :s3
        summary[:records] << { dataset_key: dataset.key, status: :skipped, message: "ingest directory not found" }
        return
      end

      storage_keys = ingest_root.file_keys(dataset.key).sort
      if !directory_exists && storage_keys.empty?
        summary[:records] << { dataset_key: dataset.key, status: :skipped, message: "ingest directory not found" }
        return
      end

      storage_keys.each do |storage_key|
        summary[:records_scanned] += 1

        binary_name = File.basename(storage_key.to_s)
        if storage_key.to_s.end_with?("/")
          next
        end

        if binary_name.blank? || !storage_key.to_s.start_with?("#{dataset.key}/") || storage_key.to_s.split("/").any? { |part| %w[. ..].include?(part) }
          summary[:skipped_invalid] += 1
          @logger.warn("Globus::IngestImportService invalid storage key for #{dataset.key}: #{storage_key}")
          summary[:records] << {
            dataset_key: dataset.key,
            storage_key: storage_key,
            status: :skipped_invalid,
            message: "invalid filename"
          }
          next
        end

        existing = dataset.datafiles.find_by(binary_name: binary_name)
        if existing
          summary[:skipped_existing] += 1
          summary[:records] << {
            dataset_key: dataset.key,
            storage_key: storage_key,
            binary_name: binary_name,
            status: :skipped_existing,
            message: "datafile already exists"
          }
          next
        end

        binary_size = ingest_root.size(storage_key)
        if @dry_run
          summary[:created] += 1
          summary[:records] << {
            dataset_key: dataset.key,
            storage_key: storage_key,
            binary_name: binary_name,
            binary_size: binary_size,
            status: :would_create
          }
          next
        end

        unless StorageManager.instance.globus_ingest_uses_draft_storage?
          StorageManager.instance.draft_root.copy_content_to(storage_key, ingest_root, storage_key)
        end

        datafile = dataset.datafiles.new(
          binary_name: binary_name,
          binary_size: binary_size,
          storage_root: StorageManager.instance.draft_root.name,
          storage_key: storage_key
        )

        Datafile.transaction(requires_new: true) do
          datafile.save!
          dataset.update!(all_globus: false, all_medusa: false) if dataset.all_globus? || dataset.all_medusa?
        end
        summary[:created] += 1
        summary[:records] << {
          dataset_key: dataset.key,
          storage_key: storage_key,
          binary_name: binary_name,
          binary_size: binary_size,
          status: :created,
          web_id: datafile.web_id
        }
      rescue StandardError => e
        summary[:failed] += 1
        summary[:records] << {
          dataset_key: dataset.key,
          storage_key: storage_key,
          status: :failed,
          message: e.message
        }
        @logger.warn("Globus::IngestImportService failed for #{dataset.key} #{storage_key}: #{e.class}: #{e.message}")
      end
    end
  end
end
