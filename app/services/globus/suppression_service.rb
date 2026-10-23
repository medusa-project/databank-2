module Globus
  class SuppressionService
    def initialize(dataset, logger: Rails.logger)
      @dataset = dataset
      @logger = logger
    end

    def remove_from_public_download
      root = StorageManager.instance.globus_download_root

      @dataset.datafiles.each do |datafile|
        binary_name = datafile.binary_name.to_s.strip
        next if binary_name.blank?

        target_key = File.join(@dataset.key, binary_name)
        root.delete_content(target_key) if root.exist?(target_key)
      end

      directory_exists = root.exist?("#{@dataset.key}/")
      if directory_exists || root.root_type == :s3
        root.file_keys(@dataset.key).each { |storage_key| root.delete_content(storage_key) }
        if root.root_type == :filesystem
          root.path_to("#{@dataset.key}/").rmdir
        elsif directory_exists
          root.delete_content("#{@dataset.key}/")
        end
      end

      @dataset.update!(all_globus: false) if @dataset.all_globus

      true
    rescue StandardError => e
      @logger.warn("Globus::SuppressionService remove_from_public_download failed for #{@dataset.key}: #{e.class}: #{e.message}")
      false
    end
  end
end
