require "rails_helper"

RSpec.describe DatasetAccessGrant, type: :model do
  let(:dataset) { create(:dataset) }

  it "normalizes email before validation" do
    grant = described_class.create!(dataset: dataset, email: " Curator@Example.edu ", access_level: :viewer)

    expect(grant.email).to eq("curator@example.edu")
  end

  it "rejects duplicate emails for the same dataset case-insensitively" do
    described_class.create!(dataset: dataset, email: "curator@example.edu", access_level: :viewer)
    duplicate = described_class.new(dataset: dataset, email: "CURATOR@example.edu", access_level: :editor)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to be_present
  end

  it "allows the same email for a different dataset" do
    other_dataset = create(:dataset)
    described_class.create!(dataset: dataset, email: "curator@example.edu", access_level: :viewer)
    other_grant = described_class.new(dataset: other_dataset, email: "CURATOR@example.edu", access_level: :editor)

    expect(other_grant).to be_valid
  end

  it "normalizes email values in the class helper" do
    expect(described_class.normalize_email_value(" Curator@Example.edu ")).to eq("curator@example.edu")
    expect(described_class.normalize_email_value("   ")).to be_nil
  end

  it "filters grants by normalized email" do
    matching = described_class.create!(dataset: dataset, email: "curator@example.edu", access_level: :viewer)
    described_class.create!(dataset: create(:dataset), email: "someoneelse@example.edu", access_level: :viewer)

    expect(described_class.for_email(" CURATOR@example.edu ")).to contain_exactly(matching)
    expect(described_class.for_email("   ")).to be_empty
  end

  it "reports read access when a matching grant exists" do
    described_class.create!(dataset: dataset, email: "curator@example.edu", access_level: :viewer)

    expect(described_class.grants_read_access?(dataset_id: dataset.id, email: "CURATOR@example.edu")).to be(true)
    expect(described_class.grants_read_access?(dataset_id: dataset.id, email: "other@example.edu")).to be(false)
  end

  it "reports edit access only for editor grants" do
    described_class.create!(dataset: dataset, email: "viewer@example.edu", access_level: :viewer)
    described_class.create!(dataset: dataset, email: "editor@example.edu", access_level: :editor)

    expect(described_class.grants_edit_access?(dataset_id: dataset.id, email: "editor@example.edu")).to be(true)
    expect(described_class.grants_edit_access?(dataset_id: dataset.id, email: "viewer@example.edu")).to be(false)
  end
end
