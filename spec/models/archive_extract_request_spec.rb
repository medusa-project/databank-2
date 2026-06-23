require "rails_helper"

RSpec.describe ArchiveExtractRequest, type: :model do
  it "defines expected status enum values" do
    expect(described_class.statuses).to eq(
      "pending" => "pending",
      "sent" => "sent",
      "success" => "success",
      "failed" => "failed"
    )
  end

  it "is invalid without a datafile" do
    request = described_class.new(status: :pending)

    expect(request).not_to be_valid
    expect(request.errors[:datafile]).to be_present
  end

  it "enforces one request per datafile" do
    datafile = create(:datafile)
    described_class.create!(datafile: datafile, status: :pending)

    duplicate = described_class.new(datafile: datafile, status: :sent)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:datafile_id]).to be_present
  end

  it "exposes errors through archive extract response" do
    request = described_class.create!(datafile: create(:datafile), status: :pending)
    response = ArchiveExtractResponse.create!(archive_extract_request: request, status: "error", response: {})
    error = ArchiveExtractError.create!(archive_extract_response: response, error_type: "extract", error_report: "bad archive")

    expect(request.archive_extract_errors).to contain_exactly(error)
  end

  it "destroys dependent response and response errors" do
    request = described_class.create!(datafile: create(:datafile), status: :pending)
    response = ArchiveExtractResponse.create!(archive_extract_request: request, status: "success", response: {})
    ArchiveExtractError.create!(archive_extract_response: response, error_type: "warn", error_report: "none")

    expect { request.destroy }
      .to change(ArchiveExtractResponse, :count).by(-1)
      .and change(ArchiveExtractError, :count).by(-1)
  end
end
