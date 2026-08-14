module Doi
  class SuppressionService
    def initialize(dataset, logger: Rails.logger)
      @dataset = dataset
      @logger = logger
    end

    def suppress_metadata
      return true if @dataset.identifier.blank?
      return true unless datacite_enabled?

      datacite_client.hide_doi!(doi: @dataset.identifier)
      true
    rescue StandardError => e
      @logger.warn("Doi::SuppressionService suppress_metadata failed for #{@dataset.key}: #{e.class}: #{e.message}")
      false
    end

    def unsuppress_metadata
      return true if @dataset.identifier.blank?
      return true unless datacite_enabled?

      datacite_client.update_doi!(
        dataset: @dataset,
        doi: @dataset.identifier,
        dataset_url: dataset_url,
        event: "publish"
      )
      true
    rescue StandardError => e
      @logger.warn("Doi::SuppressionService unsuppress_metadata failed for #{@dataset.key}: #{e.class}: #{e.message}")
      false
    end

    private

    def datacite_client
      @datacite_client ||= DataciteClient.new(
        api_base_url: IdbConfig.fetch(:doi, :api_base_url),
        username: IdbConfig.fetch(:doi, :username),
        password: IdbConfig.fetch(:doi, :password)
      )
    end

    def datacite_enabled?
      %i[api_base_url username password].all? { |key| IdbConfig.fetch(:doi, key).present? }
    end

    def dataset_url
      root = IdbConfig.fetch(:app, :url, default: "http://127.0.0.1:3000")
      "#{root}/datasets/#{@dataset.key}"
    end
  end
end
