require "rails_helper"

RSpec.describe Doi::DataciteClient, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:dataset) { create(:dataset, title: "Published dataset", publisher: nil) }
  let(:doi) { "10.5072/example" }
  let(:dataset_url) { "https://databank.test/datasets/#{dataset.key}" }
  let(:http_response) { Net::HTTPCreated.new("1.1", "201", "Created") }
  let(:http) { instance_double(Net::HTTP) }
  let(:client) do
    described_class.new(
      api_base_url: "https://api.example.test",
      username: "user",
      password: "secret"
    )
  end

  before do
    allow(Net::HTTP).to receive(:start).with("api.example.test", 443, use_ssl: true).and_yield(http)
    allow(http).to receive(:request) do |request|
      @request = request
      http_response
    end
  end

  it "registers a DOI with the expected request payload" do
    dataset.related_materials.create!(
      title: "Related article",
      uri: "https://doi.org/10.1000/example",
      uri_type: "DOI",
      datacite_list: "IsSupplementTo,IsCitedBy"
    )

    result = client.register_doi!(dataset: dataset, doi: doi, dataset_url: dataset_url)

    expect(result).to be(true)
    expect(@request).to be_a(Net::HTTP::Post)
    expect(@request.path).to eq("/dois")
    expect(@request["Content-Type"]).to eq("application/vnd.api+json")
    expect(@request["Authorization"]).to eq("Basic #{Base64.strict_encode64('user:secret')}")

    payload = JSON.parse(@request.body)
    expect(payload.fetch("data").fetch("type")).to eq("dois")
    attributes = payload.fetch("data").fetch("attributes")
    expect(attributes).to include(
      "doi" => "10.5072/example",
      "event" => "publish",
      "url" => "https://databank.test/datasets/#{dataset.key}",
      "publisher" => "Illinois Data Bank"
    )
    expect(attributes.fetch("titles")).to eq([ { "title" => "Published dataset" } ])
    expect(attributes.fetch("types")).to eq({ "resourceTypeGeneral" => "Dataset" })
    expect(attributes.fetch("relatedIdentifiers")).to eq([
      {
        "relatedIdentifier" => "https://doi.org/10.1000/example",
        "relatedIdentifierType" => "DOI",
        "relationType" => "IsSupplementTo"
      },
      {
        "relatedIdentifier" => "https://doi.org/10.1000/example",
        "relatedIdentifierType" => "DOI",
        "relationType" => "IsCitedBy"
      }
    ])
  end

  it "uses the dataset published year when available" do
    dataset.update!(published_at: Time.zone.parse("2024-01-15 10:00:00"))

    client.register_doi!(dataset: dataset, doi: doi, dataset_url: dataset_url)

    expect(JSON.parse(@request.body).dig("data", "attributes", "publicationYear")).to eq(2024)
  end

  it "uses the current year for an unpublished dataset" do
    travel_to(Time.zone.parse("2026-10-13 12:00:00")) do
      client.register_doi!(dataset: dataset, doi: doi, dataset_url: dataset_url)

      expect(JSON.parse(@request.body).dig("data", "attributes", "publicationYear")).to eq(2026)
    end
  end

  it "omits materials without a URI and defaults identifier type to URL" do
    dataset.related_materials.create!(title: "Citation only")
    dataset.related_materials.create!(
      title: "Related website",
      uri: "https://example.test/article",
      datacite_list: "IsSupplementTo"
    )

    client.register_doi!(dataset: dataset, doi: doi, dataset_url: dataset_url)

    expect(JSON.parse(@request.body).dig("data", "attributes", "relatedIdentifiers")).to eq([
      {
        "relatedIdentifier" => "https://example.test/article",
        "relatedIdentifierType" => "URL",
        "relationType" => "IsSupplementTo"
      }
    ])
  end

  describe "#update_doi!" do
    let(:http_response) { Net::HTTPOK.new("1.1", "200", "OK") }

    it "updates metadata and publishes the existing DOI" do
      dataset.update!(publisher: "Custom Publisher", published_at: Time.zone.parse("2024-01-15 10:00:00"))
      dataset.related_materials.create!(
        title: "Related website",
        uri: "https://example.test/article",
        datacite_list: "IsCitedBy"
      )

      expect(client.update_doi!(dataset: dataset, doi: doi, dataset_url: dataset_url)).to be(true)
      expect(@request).to be_a(Net::HTTP::Put)
      expect(@request.path).to eq("/dois/#{doi}")
      expect(@request["Content-Type"]).to eq("application/vnd.api+json")
      expect(@request["Authorization"]).to eq("Basic #{Base64.strict_encode64('user:secret')}")
      expect(JSON.parse(@request.body)).to eq(
        "data" => {
          "id" => doi,
          "type" => "dois",
          "attributes" => {
            "event" => "publish",
            "url" => dataset_url,
            "titles" => [ { "title" => "Published dataset" } ],
            "publisher" => "Custom Publisher",
            "publicationYear" => 2024,
            "types" => { "resourceTypeGeneral" => "Dataset" },
            "relatedIdentifiers" => [
              {
                "relatedIdentifier" => "https://example.test/article",
                "relatedIdentifierType" => "URL",
                "relationType" => "IsCitedBy"
              }
            ]
          }
        }
      )
    end

    it "honors an explicit event and defaults unpublished metadata" do
      travel_to(Time.zone.parse("2026-10-13 12:00:00")) do
        client.update_doi!(dataset: dataset, doi: doi, dataset_url: dataset_url, event: "register")

        expect(JSON.parse(@request.body).dig("data", "attributes")).to include(
          "event" => "register",
          "publisher" => "Illinois Data Bank",
          "publicationYear" => 2026,
          "relatedIdentifiers" => []
        )
      end
    end
  end

  describe "#hide_doi!" do
    let(:http_response) { Net::HTTPOK.new("1.1", "200", "OK") }

    it "sends only the hide event for the existing DOI" do
      expect(client.hide_doi!(doi: doi)).to be(true)
      expect(@request).to be_a(Net::HTTP::Put)
      expect(@request.path).to eq("/dois/#{doi}")
      expect(@request["Content-Type"]).to eq("application/vnd.api+json")
      expect(@request["Authorization"]).to eq("Basic #{Base64.strict_encode64('user:secret')}")
      expect(JSON.parse(@request.body)).to eq(
        "data" => {
          "id" => doi,
          "type" => "dois",
          "attributes" => { "event" => "hide" }
        }
      )
    end
  end

  {
    register_doi!: "registration",
    update_doi!: "update",
    hide_doi!: "hide"
  }.each do |operation, action|
    describe "failures from #{operation}" do
      let(:arguments) do
        operation == :hide_doi! ? { doi: doi } : { dataset: dataset, doi: doi, dataset_url: dataset_url }
      end

      it "includes the HTTP status and response body in the error" do
        response = instance_double(Net::HTTPBadRequest, code: "400", body: "bad payload")
        allow(http).to receive(:request).and_return(response)

        expect do
          client.public_send(operation, **arguments)
        end.to raise_error(RuntimeError, "DataCite DOI #{action} failed (400): bad payload")
      end

      it "propagates transport failures" do
        allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout, "connection timed out")

        expect do
          client.public_send(operation, **arguments)
        end.to raise_error(Net::OpenTimeout, "connection timed out")
      end
    end
  end
end
