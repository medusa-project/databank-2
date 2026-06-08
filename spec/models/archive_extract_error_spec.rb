require "rails_helper"

RSpec.describe ArchiveExtractError, type: :model do
  it "is invalid without archive extract response" do
    error = described_class.new(error_type: "extract", error_report: "failed")

    expect(error).not_to be_valid
    expect(error.errors[:archive_extract_response]).to be_present
  end

  it "belongs to archive extract response" do
    request = ArchiveExtractRequest.create!(datafile: create(:datafile), status: :pending)
    response = ArchiveExtractResponse.create!(archive_extract_request: request, status: "error", response: {})
    error = described_class.create!(archive_extract_response: response, error_type: "extract", error_report: "failed")

    expect(error.archive_extract_response).to eq(response)
  end
end
