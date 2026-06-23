require "rails_helper"

RSpec.describe VersionRequest, type: :model do
  let(:dataset) { create(:dataset) }

  it "defaults to pending status" do
    request = described_class.create!(
      dataset: dataset,
      requester_email: "requester@example.edu",
      requester_name: "Requester",
      requested_at: Time.current
    )

    expect(request.status).to eq("pending")
  end

  it "requires requester attributes" do
    request = described_class.new(dataset: dataset)

    expect(request).not_to be_valid
    expect(request.errors[:requester_email]).to be_present
    expect(request.errors[:requester_name]).to be_present
    expect(request.errors[:requested_at]).to be_present
  end

  it "allows an approved dataset association" do
    approved_dataset = create(:dataset)
    request = described_class.create!(
      dataset: dataset,
      approved_dataset: approved_dataset,
      requester_email: "requester@example.edu",
      requester_name: "Requester",
      requested_at: Time.current,
      status: :approved
    )

    expect(request.approved_dataset).to eq(approved_dataset)
    expect(request.status).to eq("approved")
  end
end
