require "digest"
require "fileutils"
require "json"
require "net/http"
require "uri"

module Migration
  class SampleFetchService
    DEFAULT_LIST_PATH = Rails.root.join("working", "datasets.json")
    DEFAULT_OUTPUT_ROOT = Rails.root.join("working", "migration_samples")

    attr_reader :list_path, :output_root, :limit, :open_timeout, :read_timeout

    def initialize(list_path: DEFAULT_LIST_PATH, output_root: DEFAULT_OUTPUT_ROOT, limit: nil, open_timeout: 10, read_timeout: 30)
      @list_path = Pathname(list_path)
      @output_root = Pathname(output_root)
      @limit = limit
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call
      run_dir = output_root.join(Time.current.utc.strftime("%Y%m%dT%H%M%SZ"))
      data_dir = run_dir.join("datasets")
      FileUtils.mkdir_p(data_dir)

      entries = load_list
      entries = entries.first(limit) if limit.to_i.positive?

      summary = {
        run_dir: run_dir.to_s,
        source_list: list_path.to_s,
        total_listed: entries.length,
        fetched: 0,
        failed: 0,
        records: []
      }

      entries.each do |entry|
        identifier = entry["identifier"].to_s
        url = entry["url"].to_s.strip

        if url.blank?
          summary[:failed] += 1
          summary[:records] << { identifier: identifier, url: url, status: "failed", error: "missing url" }
          next
        end

        payload = fetch_json(url)
        payload["url"] ||= url

        key = payload["url"].to_s[/IDB-\d{7}/] || payload["identifier"].to_s.gsub(/[\W]+/, "_")
        filename = "#{key.presence || Digest::SHA256.hexdigest(url)[0, 12]}.json"
        path = data_dir.join(filename)
        File.write(path, JSON.pretty_generate(payload))

        summary[:fetched] += 1
        summary[:records] << {
          identifier: payload["identifier"] || identifier,
          url: url,
          status: "fetched",
          file: path.to_s
        }
      rescue StandardError => e
        summary[:failed] += 1
        summary[:records] << { identifier: identifier, url: url, status: "failed", error: e.message }
      end

      File.write(run_dir.join("summary.json"), JSON.pretty_generate(summary))
      summary
    end

    private

    def load_list
      JSON.parse(File.read(list_path.to_s))
    end

    def fetch_json(url)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: open_timeout, read_timeout: read_timeout) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        request["Accept"] = "application/json"
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "fetch failed: #{response.code} #{response.message}"
      end

      JSON.parse(response.body)
    end
  end
end
