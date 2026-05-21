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

  around do |example|
    original = ENV.to_h
    begin
      example.run
    ensure
      ENV.replace(original)
    end
  end

  it "returns generated DOI when DataCite is not configured" do
    %w[DATACITE_API_BASE_URL DATACITE_USERNAME DATACITE_PASSWORD DATACITE_STRICT].each { |key| ENV.delete(key) }

    doi = described_class.new(dataset).mint_for_publish!

    expect(doi).to eq("10.5555/#{dataset.key}")
  end

  it "returns existing identifier without reminting" do
    dataset.update!(identifier: "10.5555/existing-doi")

    doi = described_class.new(dataset).mint_for_publish!

    expect(doi).to eq("10.5555/existing-doi")
  end
end
