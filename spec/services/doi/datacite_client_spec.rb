require "rails_helper"

RSpec.describe Doi::DataciteClient, type: :service do
  let(:dataset) { create(:dataset, title: "Published dataset", publisher: nil) }
  let(:client) do
    described_class.new(
      api_base_url: "https://api.example.test",
      username: "user",
      password: "secret"
    )
  end

  it "registers a DOI with the expected request payload" do
    response = Net::HTTPSuccess.new("1.1", "201", "Created")
    http = instance_double(Net::HTTP)
    captured_request = nil

    allow(Net::HTTP).to receive(:start).with("api.example.test", 443, use_ssl: true).and_yield(http)
    allow(http).to receive(:request) do |request|
      captured_request = request
      response
    end

    result = client.register_doi!(dataset: dataset, doi: "10.5072/example", dataset_url: "https://databank.test/datasets/#{dataset.key}")

    expect(result).to be(true)
    expect(captured_request["Content-Type"]).to eq("application/vnd.api+json")
    expect(captured_request["Authorization"]).to start_with("Basic ")

    payload = JSON.parse(captured_request.body)
    attributes = payload.fetch("data").fetch("attributes")
    expect(attributes).to include(
      "doi" => "10.5072/example",
      "event" => "publish",
      "url" => "https://databank.test/datasets/#{dataset.key}",
      "publisher" => "Illinois Data Bank"
    )
    expect(attributes.fetch("titles")).to eq([ { "title" => "Published dataset" } ])
    expect(attributes.fetch("types")).to eq({ "resourceTypeGeneral" => "Dataset" })
  end

  it "raises when DataCite responds with a non-success status" do
    response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    response.instance_variable_set(:@read, true)
    response.body = "bad payload"
    http = instance_double(Net::HTTP, request: response)

    allow(Net::HTTP).to receive(:start).and_yield(http)

    expect do
      client.register_doi!(dataset: dataset, doi: "10.5072/example", dataset_url: "https://databank.test/datasets/#{dataset.key}")
    end.to raise_error(RuntimeError, /DataCite DOI registration failed \(400\): bad payload/)
  end

  it "uses the dataset published year when available" do
    response = Net::HTTPSuccess.new("1.1", "201", "Created")
    http = instance_double(Net::HTTP)
    captured_request = nil
    dataset.update!(published_at: Time.zone.parse("2024-01-15 10:00:00"))

    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request) do |request|
      captured_request = request
      response
    end

    client.register_doi!(dataset: dataset, doi: "10.5072/example", dataset_url: "https://databank.test/datasets/#{dataset.key}")

    payload = JSON.parse(captured_request.body)
    expect(payload.dig("data", "attributes", "publicationYear")).to eq(2024)
  end
end
