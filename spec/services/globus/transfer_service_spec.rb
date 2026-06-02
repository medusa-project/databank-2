require "rails_helper"

RSpec.describe Globus::TransferService, type: :service do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-4555555",
      title: "Globus Transfer Dataset",
      description: "Dataset for transfer event",
      owner_uid: "owner-globus",
      depositor_name: "Owner Globus",
      depositor_email: "owner-globus@example.edu",
      identifier: "10.5555/IDB-4555555",
      publication_state: :published,
      published_at: Time.current
    )
  end

  before do
    dataset.datafiles.create!(web_id: "abcde", binary_name: "analysis.csv")
  end

  before do
    globus_config = {
      transfer_enabled: "true",
      transfer_endpoint: "https://globus.example.org/api/transfers",
      transfer_token: "secret-token",
      source_collection: "source-collection-id",
      destination_collection: "dest-collection-id",
      source_base_path: "/source-root",
      destination_base_path: "/dest-root"
    }

    allow(IdbConfig).to receive(:fetch) do |*keys, default: nil|
      value = keys.reduce({ globus: globus_config }) do |memo, key|
        break nil unless memo.respond_to?(:[])

        memo[key.to_sym] || memo[key.to_s]
      end

      value.nil? ? default : value
    end
  end

  it "submits transfer payload to Globus endpoint" do
    service = described_class.new
    fake_http = instance_double("Net::HTTP")
    fake_response = instance_double("Net::HTTPResponse", code: "202")
    captured = {}

    allow(fake_http).to receive(:request) do |request|
      captured[:request] = request
      fake_response
    end

    allow(Net::HTTP).to receive(:start) do |host, port, use_ssl:, &block|
      captured[:host] = host
      captured[:port] = port
      captured[:use_ssl] = use_ssl
      block.call(fake_http)
    end

    result = service.submit_dataset_transfer(dataset)

    expect(result).to eq(true)
    expect(captured[:host]).to eq("globus.example.org")
    expect(captured[:use_ssl]).to eq(true)
    expect(captured[:request]["Authorization"]).to eq("Bearer secret-token")

    payload = JSON.parse(captured[:request].body)
    expect(payload["label"]).to eq("databank2 dataset IDB-4555555")
    expect(payload["source_collection"]).to eq("source-collection-id")
    expect(payload["destination_collection"]).to eq("dest-collection-id")
    expect(payload["items"]).to include(
      hash_including(
        "source_path" => "/source-root/IDB-4555555/analysis.csv",
        "destination_path" => "/dest-root/IDB-4555555/analysis.csv"
      )
    )
  end

  it "is disabled when required config is missing" do
    allow(IdbConfig).to receive(:fetch).with(:globus, :transfer_token, default: "").and_return("")

    service = described_class.new
    expect(service.enabled?).to eq(false)
    expect(service.submit_dataset_transfer(dataset)).to eq(false)
  end
end
