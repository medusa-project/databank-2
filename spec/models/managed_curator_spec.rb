require "rails_helper"

RSpec.describe ManagedCurator, type: :model do
  it "normalizes email before validation" do
    curator = described_class.create!(email: " Curator@Example.edu ")

    expect(curator.email).to eq("curator@example.edu")
  end

  it "rejects invalid email addresses" do
    curator = described_class.new(email: "not-an-email")

    expect(curator).not_to be_valid
    expect(curator.errors[:email]).to be_present
  end

  it "rejects duplicate emails case-insensitively" do
    described_class.create!(email: "curator@example.edu")
    duplicate = described_class.new(email: "CURATOR@example.edu")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to be_present
  end
end
