require "base64"
require "json"
require "net/http"
require "uri"

module Doi
  class DataciteClient
    def initialize(api_base_url:, username:, password:)
      @api_base_url = api_base_url
      @username = username
      @password = password
    end

    def register_doi!(dataset:, doi:, dataset_url:)
      uri = URI.parse("#{@api_base_url}/dois")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/vnd.api+json"
      request["Authorization"] = "Basic #{Base64.strict_encode64("#{@username}:#{@password}")}"
      request.body = registration_payload(dataset: dataset, doi: doi, dataset_url: dataset_url).to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      return true if response.is_a?(Net::HTTPSuccess)

      raise "DataCite DOI registration failed (#{response.code}): #{response.body}"
    end

    private

    def registration_payload(dataset:, doi:, dataset_url:)
      publication_year = (dataset.published_at || Time.current).year

      {
        data: {
          type: "dois",
          attributes: {
            doi: doi,
            event: "publish",
            url: dataset_url,
            titles: [
              { title: dataset.title }
            ],
            publisher: dataset.publisher.presence || "Illinois Data Bank",
            publicationYear: publication_year,
            types: {
              resourceTypeGeneral: "Dataset"
            }
          }
        }
      }
    end
  end
end
