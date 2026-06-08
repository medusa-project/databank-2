module Globus
  class PublicCopyService
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
        copied: 0,
        skipped_existing: 0,
        skipped_non_public: 0,
        skipped_invalid: 0,
        failed: 0,
        records: []
      }

      datasets_scope.each do |dataset|
        break if @dataset_limit && summary[:datasets_scanned] >= @dataset_limit

        summary[:datasets_scanned] += 1
        copy_dataset(dataset: dataset, summary: summary)
      end

      summary
    end

    private

    def datasets_scope
      scope = Dataset.includes(:datafiles).order(:id)
      @dataset_key.present? ? scope.where(key: @dataset_key) : scope
    end

    def copy_dataset(dataset:, summary:)
      unless dataset.files_publicly_readable_now?
        summary[:skipped_non_public] += dataset.datafiles.count
        summary[:records] << {
          dataset_key: dataset.key,
          status: :skipped_non_public,
          message: "dataset files are not publicly readable"
        }
        return
      end

      dataset.datafiles.each do |datafile|
        summary[:records_scanned] += 1
        source_root = datafile.current_root
        source_key = datafile.storage_key.to_s

        if source_root.nil? || source_key.blank?
          summary[:skipped_invalid] += 1
          summary[:records] << {
            dataset_key: dataset.key,
            datafile_web_id: datafile.web_id,
            status: :skipped_invalid,
            message: "missing source root or storage key"
          }
          next
        end

        binary_name = datafile.binary_name.to_s.strip
        binary_name = File.basename(source_key) if binary_name.blank?
        target_key = File.join(dataset.key, binary_name)

        destination_root = StorageManager.instance.globus_download_root
        if destination_root.exist?(target_key)
          summary[:skipped_existing] += 1
          summary[:records] << {
            dataset_key: dataset.key,
            datafile_web_id: datafile.web_id,
            source_key: source_key,
            target_key: target_key,
            status: :skipped_existing
          }
          next
        end

        if @dry_run
          summary[:copied] += 1
          summary[:records] << {
            dataset_key: dataset.key,
            datafile_web_id: datafile.web_id,
            source_key: source_key,
            target_key: target_key,
            status: :would_copy
          }
          next
        end

        destination_root.copy_content_to(target_key, source_root, source_key)
        summary[:copied] += 1
        summary[:records] << {
          dataset_key: dataset.key,
          datafile_web_id: datafile.web_id,
          source_key: source_key,
          target_key: target_key,
          status: :copied
        }
      rescue StandardError => e
        summary[:failed] += 1
        summary[:records] << {
          dataset_key: dataset.key,
          datafile_web_id: datafile.web_id,
          source_key: source_key,
          status: :failed,
          message: e.message
        }
        @logger.warn("Globus::PublicCopyService failed for #{dataset.key} #{source_key}: #{e.class}: #{e.message}")
      end
    end
  end
end
