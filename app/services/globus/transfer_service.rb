require "json"
require "net/http"
require "uri"

module Globus
  class TransferService
    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def enabled?
      transfer_enabled? && transfer_endpoint.present? && transfer_token.present? &&
        source_collection.present? && destination_collection.present?
    end

    def submit_dataset_transfer(dataset)
      return false unless enabled?

      uri = URI.parse(transfer_endpoint)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{transfer_token}"
        request.body = JSON.generate(transfer_payload(dataset))
        http.request(request)
      end

      response.code.to_i.between?(200, 299)
    rescue StandardError => e
      @logger.warn("Globus::TransferService failed: #{e.class}: #{e.message}")
      false
    end

    private

    def transfer_payload(dataset)
      {
        label: "databank2 dataset #{dataset.key}",
        source_collection: source_collection,
        destination_collection: destination_collection,
        items: transfer_items(dataset),
        metadata: {
          dataset_id: dataset.id,
          dataset_key: dataset.key,
          dataset_identifier: dataset.identifier
        }
      }
    end

    def transfer_items(dataset)
      dataset.datafiles.map do |datafile|
        filename = datafile.binary_name.presence || "file-#{datafile.web_id}"
        {
          source_path: build_path(source_base_path, dataset.key, filename),
          destination_path: build_path(destination_base_path, dataset.key, filename)
        }
      end
    end

    def build_path(base, *parts)
      path = ([ base.presence || "/" ] + parts.compact.map(&:to_s)).join("/")
      path = "/#{path}" unless path.start_with?("/")
      path.gsub(%r{/+}, "/")
    end

    def transfer_enabled?
      ENV.fetch("ENABLE_GLOBUS_TRANSFER", "false").casecmp("true").zero?
    end

    def transfer_endpoint
      ENV["GLOBUS_TRANSFER_ENDPOINT"].to_s.strip
    end

    def transfer_token
      ENV["GLOBUS_TRANSFER_TOKEN"].to_s.strip
    end

    def source_collection
      ENV["GLOBUS_SOURCE_COLLECTION"].to_s.strip
    end

    def destination_collection
      ENV["GLOBUS_DESTINATION_COLLECTION"].to_s.strip
    end

    def source_base_path
      ENV.fetch("GLOBUS_SOURCE_BASE_PATH", "/")
    end

    def destination_base_path
      ENV.fetch("GLOBUS_DESTINATION_BASE_PATH", "/")
    end
  end
end
