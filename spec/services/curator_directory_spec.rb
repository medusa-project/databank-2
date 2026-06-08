require "rails_helper"

RSpec.describe CuratorDirectory, type: :service do
  before do
    allow(IdbConfig).to receive(:fetch).with(:curator, :core_emails).and_return([ " Core@One.edu,second@two.edu ", "third@three.edu", nil ])
  end

  it "normalizes configured core emails" do
    expect(described_class.core_emails).to eq([ "core@one.edu", "second@two.edu", "third@three.edu" ])
  end

  it "matches core emails case-insensitively" do
    expect(described_class.core_email?(" CORE@one.edu ")).to be(true)
    expect(described_class.core_email?("missing@example.edu")).to be(false)
    expect(described_class.core_email?(nil)).to be(false)
  end

  it "matches managed emails case-insensitively" do
    create(:user, email: "admin@example.edu", role: :admin)
    ManagedCurator.create!(email: "managed@example.edu")

    expect(described_class.managed_email?(" MANAGED@example.edu ")).to be(true)
    expect(described_class.managed_email?("")).to be(false)
  end

  it "returns whether any curator source includes an email" do
    ManagedCurator.create!(email: "managed@example.edu")

    expect(described_class.includes_email?("core@one.edu")).to be(true)
    expect(described_class.includes_email?("managed@example.edu")).to be(true)
    expect(described_class.includes_email?("other@example.edu")).to be(false)
  end

  it "returns managed emails sorted by email" do
    ManagedCurator.create!(email: "zeta@example.edu")
    ManagedCurator.create!(email: "alpha@example.edu")

    expect(described_class.managed_emails).to eq([ "alpha@example.edu", "zeta@example.edu" ])
  end

  it "combines core, managed, and dynamic user emails into unique recipients" do
    ManagedCurator.create!(email: "managed@example.edu")
    create(:user, email: "admin@example.edu", role: :admin)
    create(:user, email: "curator@example.edu", role: :curator)
    create(:user, email: "viewer@example.edu", role: :depositor)

    expect(described_class.review_recipients).to eq([
      "core@one.edu",
      "second@two.edu",
      "third@three.edu",
      "managed@example.edu",
      "admin@example.edu",
      "curator@example.edu"
    ])
  end
end
