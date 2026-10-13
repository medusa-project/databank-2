require "rails_helper"

RSpec.describe Doi::SuppressionService, type: :service do
  let(:dataset) { create(:dataset, identifier: "10.5072/example") }
  let(:client) { instance_double(Doi::DataciteClient, hide_doi!: true, update_doi!: true) }
  let(:logger) { instance_double(ActiveSupport::Logger, warn: nil) }
  let(:service) { described_class.new(dataset, logger: logger) }

  before do
    expect(Net::HTTP).not_to receive(:start)
    allow(IdbConfig).to receive(:fetch).and_call_original
    allow(IdbConfig).to receive(:fetch).with(:doi, :api_base_url).and_return("https://api.example.test")
    allow(IdbConfig).to receive(:fetch).with(:doi, :username).and_return("user")
    allow(IdbConfig).to receive(:fetch).with(:doi, :password).and_return("secret")
    allow(IdbConfig).to receive(:fetch).with(:app, :url, default: "http://127.0.0.1:3000").and_return("https://databank.test")
    allow(Doi::DataciteClient).to receive(:new).with(
      api_base_url: "https://api.example.test", username: "user", password: "secret"
    ).and_return(client)
  end

  {
    suppress_metadata: :hide_doi!,
    unsuppress_metadata: :update_doi!
  }.each do |operation, client_method|
    describe "##{operation}" do
      it "succeeds without contacting DataCite when the identifier is missing" do
        dataset.update!(identifier: nil)

        expect(service.public_send(operation)).to be(true)
        expect(Doi::DataciteClient).not_to have_received(:new)
        expect(client).not_to have_received(client_method)
      end

      %i[api_base_url username password].each do |key|
        it "succeeds without contacting DataCite when #{key} is missing" do
          allow(IdbConfig).to receive(:fetch).with(:doi, key).and_return("")

          expect(service.public_send(operation)).to be(true)
          expect(Doi::DataciteClient).not_to have_received(:new)
          expect(client).not_to have_received(client_method)
        end
      end

      it "returns false and logs context when DataCite fails" do
        allow(client).to receive(client_method).and_raise(Net::OpenTimeout, "connection timed out")

        expect(service.public_send(operation)).to be(false)
        expect(logger).to have_received(:warn).with(
          "Doi::SuppressionService #{operation} failed for #{dataset.key}: Net::OpenTimeout: connection timed out"
        )
      end
    end
  end

  it "hides metadata for the existing DOI" do
    expect(service.suppress_metadata).to be(true)
    expect(client).to have_received(:hide_doi!).with(doi: dataset.identifier)
    expect(client).not_to have_received(:update_doi!)
    expect(logger).not_to have_received(:warn)
  end

  it "republishes metadata with the dataset URL when unsuppressing" do
    expect(service.unsuppress_metadata).to be(true)
    expect(client).to have_received(:update_doi!).with(
      dataset: dataset,
      doi: dataset.identifier,
      dataset_url: "https://databank.test/datasets/#{dataset.key}",
      event: "publish"
    )
    expect(client).not_to have_received(:hide_doi!)
    expect(logger).not_to have_received(:warn)
  end
end
