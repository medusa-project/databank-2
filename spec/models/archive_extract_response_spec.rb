require "rails_helper"

RSpec.describe ArchiveExtractResponse, type: :model do
  it "is invalid without an archive extract request" do
    response = described_class.new(status: "success", response: {})

    expect(response).not_to be_valid
    expect(response.errors[:archive_extract_request]).to be_present
  end

  it "is invalid without status" do
    request = ArchiveExtractRequest.create!(datafile: create(:datafile), status: :pending)
    response = described_class.new(archive_extract_request: request, response: {})

    expect(response).not_to be_valid
    expect(response.errors[:status]).to be_present
  end

  it "destroys dependent errors" do
    request = ArchiveExtractRequest.create!(datafile: create(:datafile), status: :pending)
    response = described_class.create!(archive_extract_request: request, status: "error", response: {})
    ArchiveExtractError.create!(archive_extract_response: response, error_type: "extract", error_report: "boom")

    expect { response.destroy }.to change(ArchiveExtractError, :count).by(-1)
  end
end
