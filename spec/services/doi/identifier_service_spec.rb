require "rails_helper"

RSpec.describe Doi::IdentifierService, type: :service do
  let(:dataset) do
    Dataset.create!(
      title: "DOI test dataset",
      description: "Dataset used for DOI service testing",
      owner_uid: "owner-doi",
      depositor_name: "DOI Owner",
      depositor_email: "doi-owner@example.edu"
    )
  end

  let(:client) { instance_double(Doi::DataciteClient, register_doi!: true) }

  before do
    expect(Net::HTTP).not_to receive(:start)
    allow(IdbConfig).to receive(:fetch).and_call_original
    allow(IdbConfig).to receive(:fetch).with(:doi, :api_base_url).and_return("https://api.example.test")
    allow(IdbConfig).to receive(:fetch).with(:doi, :username).and_return("user")
    allow(IdbConfig).to receive(:fetch).with(:doi, :password).and_return("secret")
    allow(IdbConfig).to receive(:fetch).with(:doi, :strict, default: "false").and_return("false")
    allow(IdbConfig).to receive(:fetch).with(:app, :url, default: "http://127.0.0.1:3000").and_return("https://databank.test")
    allow(Doi::DataciteClient).to receive(:new).with(
      api_base_url: "https://api.example.test", username: "user", password: "secret"
    ).and_return(client)
  end

  %i[api_base_url username password].each do |key|
    it "returns generated DOI without registration when #{key} is missing" do
      allow(IdbConfig).to receive(:fetch).with(:doi, key).and_return("")

      doi = described_class.new(dataset).mint_for_publish!

      expect(doi).to eq("10.5555/#{dataset.key}")
      expect(Doi::DataciteClient).not_to have_received(:new)
      expect(client).not_to have_received(:register_doi!)
    end
  end

  it "returns existing identifier without reminting" do
    dataset.update!(identifier: "10.5555/existing-doi")
    expect(dataset).not_to receive(:generate_doi)

    doi = described_class.new(dataset).mint_for_publish!

    expect(doi).to eq("10.5555/existing-doi")
    expect(Doi::DataciteClient).not_to have_received(:new)
    expect(client).not_to have_received(:register_doi!)
  end

  it "registers the generated DOI with the configured client and dataset URL" do
    doi = described_class.new(dataset).mint_for_publish!

    expect(doi).to eq("10.5555/#{dataset.key}")
    expect(client).to have_received(:register_doi!).with(
      dataset: dataset,
      doi: doi,
      dataset_url: "https://databank.test/datasets/#{dataset.key}"
    )
  end

  it "returns the generated DOI and logs a warning when non-strict registration fails" do
    allow(client).to receive(:register_doi!).and_raise(Net::OpenTimeout, "connection timed out")
    allow(Rails.logger).to receive(:warn)

    expect(described_class.new(dataset).mint_for_publish!).to eq("10.5555/#{dataset.key}")
    expect(Rails.logger).to have_received(:warn).with("DataCite registration skipped: connection timed out")
  end

  it "raises the original registration error in strict mode" do
    error = RuntimeError.new("DataCite DOI registration failed (401): unauthorized")
    allow(client).to receive(:register_doi!).and_raise(error)
    allow(IdbConfig).to receive(:fetch).with(:doi, :strict, default: "false").and_return("TRUE")
    expect(Rails.logger).not_to receive(:warn)

    expect do
      described_class.new(dataset).mint_for_publish!
    end.to raise_error { |raised| expect(raised).to equal(error) }
  end
end
