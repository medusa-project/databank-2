require "rails_helper"

RSpec.describe Search::SolrIndexer, type: :service do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-1234567",
      title: "Ocean Temperatures",
      description: "Long-run coastal sensor data",
      keywords: "ocean, temperature",
      subject: "Earth Science",
      owner_uid: "owner1",
      depositor_name: "Owner One",
      depositor_email: "owner1@example.edu"
    )
  end

  it "indexes dataset to Solr update endpoint" do
    indexer = described_class.new(solr_url: "http://solr:8983/solr/datasets")
    captured = {}
    fake_http = instance_double("Net::HTTP")
    fake_response = instance_double("Net::HTTPResponse", code: "200")
    captured_request = nil

    allow(fake_http).to receive(:request) do |request|
      captured_request = request
      fake_response
    end

    allow(Net::HTTP).to receive(:start) do |host, port, use_ssl:, &block|
      captured[:host] = host
      captured[:port] = port
      captured[:use_ssl] = use_ssl
      block.call(fake_http)
    end

    result = indexer.index_dataset(dataset)

    expect(result).to eq(true)
    expect(captured[:host]).to eq("solr")
    expect(captured[:port]).to eq(8983)
    expect(captured[:use_ssl]).to eq(false)
    expect(captured_request.path).to eq("/solr/datasets/update")
    expect(captured_request["Content-Type"]).to eq("application/json")

    payload = JSON.parse(captured_request.body)
    expect(payload.dig("add", "doc", "id")).to eq("IDB-1234567")
    expect(payload.dig("add", "doc", "title_t")).to eq("Ocean Temperatures")
    expect(payload.dig("add", "doc", "publication_state_s")).to eq("draft")
  end

  it "deletes dataset by key from Solr" do
    indexer = described_class.new(solr_url: "http://solr:8983/solr/datasets/select")
    captured = {}
    fake_http = instance_double("Net::HTTP")
    fake_response = instance_double("Net::HTTPResponse", code: "200")
    captured_request = nil

    allow(fake_http).to receive(:request) do |request|
      captured_request = request
      fake_response
    end

    allow(Net::HTTP).to receive(:start) do |host, port, use_ssl:, &block|
      captured[:host] = host
      captured[:port] = port
      captured[:use_ssl] = use_ssl
      block.call(fake_http)
    end

    result = indexer.delete_dataset(dataset.key)

    expect(result).to eq(true)
    expect(captured[:host]).to eq("solr")
    expect(captured[:port]).to eq(8983)
    expect(captured[:use_ssl]).to eq(false)
    expect(captured_request.path).to eq("/solr/datasets/update")

    payload = JSON.parse(captured_request.body)
    expect(payload.dig("delete", "id")).to eq("IDB-1234567")
    expect(payload["commitWithin"]).to eq(1000)
  end

  it "returns false when Solr URL is not configured" do
    indexer = described_class.new(solr_url: nil)

    expect(Net::HTTP).not_to receive(:start)
    expect(indexer.index_dataset(dataset)).to eq(false)
    expect(indexer.delete_dataset(dataset.key)).to eq(false)
  end
end
