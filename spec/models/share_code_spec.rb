require "rails_helper"

RSpec.describe ShareCode, type: :model do
  let(:dataset) { create(:dataset) }

  it "generates a URL-safe 32-byte random code on creation" do
    share_code = dataset.create_share_code!

    expect(share_code.code).to match(/\A[A-Za-z0-9_-]{43}\z/)
    expect(share_code.dataset).to eq(dataset)
  end

  it "preserves an explicitly supplied code" do
    expect(dataset.create_share_code!(code: "existing-code").code).to eq("existing-code")
  end

  it "retries random codes that already exist" do
    dataset.create_share_code!(code: "duplicate")
    allow(SecureRandom).to receive(:urlsafe_base64).with(32, false).and_return("duplicate", "unique")

    expect(create(:dataset).create_share_code!.code).to eq("unique")
  end

  it "requires a dataset and a nonblank code" do
    share_code = described_class.new(code: "")

    expect(share_code).not_to be_valid
    expect(share_code.errors[:dataset]).to be_present
    expect(share_code.errors[:code]).to be_present
  end

  it "rejects duplicate codes and multiple codes for a dataset" do
    dataset.create_share_code!(code: "existing")
    duplicate_code = described_class.new(dataset: create(:dataset), code: "existing")
    duplicate_dataset = described_class.new(dataset: dataset, code: "other")

    expect(duplicate_code).not_to be_valid
    expect(duplicate_code.errors[:code]).to be_present
    expect(duplicate_dataset).not_to be_valid
    expect(duplicate_dataset.errors[:dataset_id]).to be_present
  end

  it "destroys the share code when its dataset is destroyed" do
    code = dataset.create_share_code!

    dataset.destroy!

    expect(described_class.exists?(code.id)).to be(false)
  end
end
