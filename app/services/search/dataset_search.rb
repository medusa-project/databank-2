require "json"
require "net/http"
require "uri"

module Search
  class DatasetSearch
    MAX_SCOPE_KEYS = 1000
    MAX_SOLR_ROWS = 200

    def initialize(scope:, query:, subject:)
      @scope = scope
      @query = query.to_s.strip
      @subject = subject.to_s.strip
    end

    def results
      return database_results if @query.blank?

      solr_results || database_results
    end

    private

    def solr_results
      return nil unless solr_enabled?

      keys = filtered_scope_for_subject.limit(MAX_SCOPE_KEYS).pluck(:key)
      return [] if keys.empty?

      docs = fetch_solr_docs(keys)
      return nil if docs.nil?

      ordered_keys = docs.filter_map { |doc| extract_key(doc) }
      return [] if ordered_keys.empty?

      datasets_by_key = Dataset.where(key: ordered_keys).index_by(&:key)
      ordered_keys.filter_map { |key| datasets_by_key[key] }
    rescue StandardError
      nil
    end

    def fetch_solr_docs(keys)
      uri = URI.parse(solr_select_url)
      params = {
        "q" => @query,
        "wt" => "json",
        "rows" => MAX_SOLR_ROWS,
        "fq" => key_filter(keys)
      }
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      json = JSON.parse(response.body)
      json.dig("response", "docs")
    end

    def extract_key(doc)
      values = [
        doc["key"],
        doc["key_s"],
        doc["id"],
        doc["id_s"],
        doc["dataset_key_s"]
      ].compact

      values.find { |value| value.is_a?(String) && value.start_with?("IDB-") }
    end

    def key_filter(keys)
      escaped = keys.map { |key| solr_escape(key) }
      "key:(#{escaped.join(' OR ')})"
    end

    def solr_escape(value)
      value.gsub(/([+\-!(){}\[\]^"~*?:\\\/]|&&|\|\|)/, '\\\\1')
    end

    def solr_enabled?
      solr_select_url.present?
    end

    def solr_select_url
      @solr_select_url ||= begin
        base = ENV["SOLR_URL"].to_s.strip
        if base.blank?
          nil
        else
          base = "#{base}/select" unless base.end_with?("/select")
          base
        end
      end
    end

    def filtered_scope_for_subject
      return @scope if @subject.blank?

      @scope.where("LOWER(subject) = ?", @subject.downcase)
    end

    def database_results
      relation = filtered_scope_for_subject

      if @query.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        relation = relation.where(
          "title ILIKE :q OR description ILIKE :q OR keywords ILIKE :q OR subject ILIKE :q",
          q: q
        )
      end

      relation.order(created_at: :desc)
    end
  end
end
