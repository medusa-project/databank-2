require "json"
require "net/http"
require "uri"

module Search
  class SolrIndexer
    COMMIT_WITHIN_MS = 1000

    def initialize(solr_url: ENV["SOLR_URL"], logger: Rails.logger)
      @solr_url = solr_url.to_s.strip
      @logger = logger
    end

    def enabled?
      solr_update_url.present?
    end

    def index_dataset(dataset)
      return false unless enabled?

      payload = {
        add: {
          doc: solr_document(dataset),
          overwrite: true,
          commitWithin: COMMIT_WITHIN_MS
        }
      }
      post_update(payload)
    end

    def delete_dataset(dataset_key)
      return false unless enabled?
      return false if dataset_key.blank?

      payload = {
        delete: { id: dataset_key },
        commitWithin: COMMIT_WITHIN_MS
      }
      post_update(payload)
    end

    private

    def solr_document(dataset)
      {
        id: dataset.key,
        key: dataset.key,
        title_t: dataset.title,
        description_t: dataset.description,
        keywords_t: dataset.keywords,
        subject_s: dataset.subject,
        publication_state_s: dataset.publication_state,
        published_at_dt: dataset.published_at&.utc&.iso8601,
        updated_at_dt: dataset.updated_at.utc.iso8601
      }.compact
    end

    def post_update(payload)
      uri = URI.parse(solr_update_url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        http.request(request)
      end

      response.code.to_i.between?(200, 299)
    rescue StandardError => e
      @logger.warn("Search::SolrIndexer failed: #{e.class}: #{e.message}")
      false
    end

    def solr_update_url
      return nil if @solr_url.blank?

      base = @solr_url.sub(%r{/select\z}, "")
      base = "#{base}/update" unless base.end_with?("/update")
      base
    end
  end
end
