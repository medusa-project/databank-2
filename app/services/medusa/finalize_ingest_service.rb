module Medusa
  # Mirrors legacy MedusaIngest#on_medusa_succeeded_message: once Medusa confirms a
  # dataset's files were ingested, switch each datafile's storage_root to "medusa"
  # (removing the now-redundant draft copy) and flag the dataset as fully preserved
  # so page loads don't need to re-check storage on every request.
  class FinalizeIngestService
    def initialize(dataset, logger: Rails.logger)
      @dataset = dataset
      @logger = logger
    end

    def call
      return false if @dataset.datafiles.empty?

      medusa_root = StorageManager.instance.medusa_root

      @dataset.datafiles.each do |datafile|
        next if datafile.storage_root == "medusa"

        target_key = target_key_for(datafile)
        next if target_key.blank?
        next unless medusa_root.exist?(target_key)

        promote_to_medusa(datafile: datafile, target_key: target_key, medusa_root: medusa_root)
      end

      update_all_medusa_flag
    rescue StandardError => e
      @logger.warn("Medusa::FinalizeIngestService failed for #{@dataset.key}: #{e.class}: #{e.message}")
      false
    end

    private

    def target_key_for(datafile)
      binary_name = datafile.binary_name.to_s.strip
      return nil if binary_name.blank?

      File.join(@dataset.key, binary_name)
    end

    def promote_to_medusa(datafile:, target_key:, medusa_root:)
      source_root = datafile.current_root
      source_key = datafile.storage_key

      if source_root && source_root.name != "medusa" && source_key.present? && source_root.exist?(source_key)
        if source_root.size(source_key) != medusa_root.size(target_key)
          @logger.warn("Medusa::FinalizeIngestService size mismatch for #{@dataset.key}/#{datafile.binary_name}, leaving draft copy in place")
          return
        end
        source_root.delete_content(source_key)
      end

      datafile.update(storage_root: "medusa", storage_key: target_key)
    end

    def update_all_medusa_flag
      all_in_medusa = @dataset.datafiles.all? { |df| df.storage_root == "medusa" }
      @dataset.update(all_medusa: true) if all_in_medusa && !@dataset.all_medusa
      all_in_medusa
    end
  end
end
