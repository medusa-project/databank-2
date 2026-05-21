module Doi
  class IdentifierService
    def initialize(dataset)
      @dataset = dataset
    end

    def mint_for_publish!
      return @dataset.identifier if @dataset.identifier.present?

      generated_doi = @dataset.generate_doi
      return generated_doi unless datacite_enabled?

      register_with_datacite!(generated_doi)
      generated_doi
    rescue StandardError => e
      raise e if datacite_strict?

      Rails.logger.warn("DataCite registration skipped: #{e.message}")
      generated_doi
    end

    private

    def register_with_datacite!(doi)
      datacite_client.register_doi!(
        dataset: @dataset,
        doi: doi,
        dataset_url: dataset_url
      )
    end

    def dataset_url
      root = ENV.fetch("APP_URL", "http://127.0.0.1:3000")
      "#{root}/datasets/#{@dataset.key}"
    end

    def datacite_client
      @datacite_client ||= DataciteClient.new(
        api_base_url: ENV.fetch("DATACITE_API_BASE_URL"),
        username: ENV.fetch("DATACITE_USERNAME"),
        password: ENV.fetch("DATACITE_PASSWORD")
      )
    end

    def datacite_enabled?
      %w[DATACITE_API_BASE_URL DATACITE_USERNAME DATACITE_PASSWORD].all? { |key| ENV[key].present? }
    end

    def datacite_strict?
      ENV["DATACITE_STRICT"].to_s.casecmp("true").zero?
    end
  end
end
