require "rails_helper"

RSpec.describe DownloaderClient, type: :model do
  let(:dataset) { create(:dataset) }

  describe ".datafiles_download_hash" do
    it "returns downloader response plus total size for valid files" do
      datafile = create(:datafile, dataset: dataset)
      allow(dataset).to receive(:record_text).and_return("dataset metadata")
      allow(described_class).to receive(:request_download_hash).and_return(
        { status: "ok", download_url: "https://download.test/file.zip", status_url: "https://download.test/status/1" }
      )

      result = described_class.datafiles_download_hash(dataset: dataset, web_ids: [ datafile.web_id ], zip_name: "bundle.zip")

      expect(result).to include(
        status: "ok",
        download_url: "https://download.test/file.zip",
        status_url: "https://download.test/status/1"
      )
      expect(result[:total_size]).to eq(datafile.binary.byte_size + "dataset metadata".bytesize)
    end

    it "returns an error when target building raises" do
      allow(Rails.logger).to receive(:warn)
      allow(described_class).to receive(:targets_arr).and_raise(StandardError.new("missing file path"))

      result = described_class.datafiles_download_hash(dataset: dataset, web_ids: [ "missing" ], zip_name: "bundle.zip")

      expect(result).to eq(status: "error", error: "internal error file path not found")
      expect(Rails.logger).to have_received(:warn).with(/error in datafiles_download_hash: missing file path/)
    end
  end

  describe ".request_download_hash" do
    it "returns a configuration error when downloader credentials are missing" do
      allow(IdbConfig).to receive(:fetch).with(:downloader, :user).and_return(nil)
      allow(IdbConfig).to receive(:fetch).with(:downloader, :password).and_return(nil)
      allow(IdbConfig).to receive(:fetch).with(:downloader, :endpoint).and_return(nil)
      allow(Rails.logger).to receive(:warn)

      result = described_class.send(:request_download_hash, medusa_request_json: "{}")

      expect(result).to eq(status: "error", error: "downloader service not configured")
      expect(Rails.logger).to have_received(:warn).with("downloader credentials not configured")
    end

    it "returns download URLs from a successful downloader response" do
      client = instance_double(Curl::Easy, body_str: { download_url: "https://download.test/file.zip", status_url: "https://download.test/status/1" }.to_json)
      allow(IdbConfig).to receive(:fetch).with(:downloader, :user).and_return("user")
      allow(IdbConfig).to receive(:fetch).with(:downloader, :password).and_return("secret")
      allow(IdbConfig).to receive(:fetch).with(:downloader, :endpoint).and_return("https://download.test")
      allow(Curl::Easy).to receive(:new).with("https://download.test").and_return(client)
      allow(client).to receive(:http_auth_types=)
      allow(client).to receive(:ssl_verify_peer=)
      allow(client).to receive(:username=)
      allow(client).to receive(:password=)
      allow(client).to receive(:post_body=)
      allow(client).to receive(:headers=)
      allow(client).to receive(:post)
      allow(client).to receive(:perform)

      result = described_class.send(:request_download_hash, medusa_request_json: "{\"root\":\"idb\"}")

      expect(result).to eq(
        status: "ok",
        download_url: "https://download.test/file.zip",
        status_url: "https://download.test/status/1"
      )
    end

    it "returns an error when the downloader response is missing a download url" do
      client = instance_double(Curl::Easy, body_str: { status_url: "https://download.test/status/1" }.to_json)
      allow(IdbConfig).to receive(:fetch).with(:downloader, :user).and_return("user")
      allow(IdbConfig).to receive(:fetch).with(:downloader, :password).and_return("secret")
      allow(IdbConfig).to receive(:fetch).with(:downloader, :endpoint).and_return("https://download.test")
      allow(Curl::Easy).to receive(:new).and_return(client)
      allow(client).to receive(:http_auth_types=)
      allow(client).to receive(:ssl_verify_peer=)
      allow(client).to receive(:username=)
      allow(client).to receive(:password=)
      allow(client).to receive(:post_body=)
      allow(client).to receive(:headers=)
      allow(client).to receive(:post)
      allow(client).to receive(:perform)

      result = described_class.send(:request_download_hash, medusa_request_json: "{}")

      expect(result).to eq(status: "error", error: "invalid response from downloader service")
    end

    it "returns an internal error when the downloader request raises" do
      allow(IdbConfig).to receive(:fetch).with(:downloader, :user).and_return("user")
      allow(IdbConfig).to receive(:fetch).with(:downloader, :password).and_return("secret")
      allow(IdbConfig).to receive(:fetch).with(:downloader, :endpoint).and_return("https://download.test")
      allow(Curl::Easy).to receive(:new).and_raise(StandardError.new("timeout"))
      allow(Rails.logger).to receive(:warn)

      result = described_class.send(:request_download_hash, medusa_request_json: "{}")

      expect(result).to eq(status: "error", error: "internal error downloading files")
      expect(Rails.logger).to have_received(:warn).with(/error interacting with medusa-downloader: StandardError timeout/)
    end
  end
end
