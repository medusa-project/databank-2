require "rails_helper"

RSpec.describe Dataset::Sharable, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:dataset) { create(:dataset) }

  it "returns the legacy placeholder when there is no sharing link" do
    expect(dataset.sharing_link).to eq("N/A no current sharing link")
    expect(dataset.current_share_code).to be_nil
    expect(dataset.has_sharing_link?).to be(false)
  end

  it "builds a configured dataset URL with the current share code" do
    allow(IdbConfig).to receive(:fetch).and_call_original
    allow(IdbConfig).to receive(:fetch).with(:app, :root_url_text, default: "http://localhost:3000").and_return("https://example.edu")
    code = dataset.create_share_code!.code

    expect(dataset.sharing_link).to eq("https://example.edu/datasets/#{dataset.key}?code=#{code}")
    expect(dataset.has_sharing_link?).to be(true)
    expect(dataset.valid_share_code?(code: code)).to be(true)
  end

  it "does not treat an upload token as a sharing link" do
    dataset.create_token!(identifier: "upload-token")

    expect(dataset.has_sharing_link?).to be(false)
    expect(dataset.valid_share_code?(code: "upload-token")).to be(false)
  end

  [ Dataset::HOLD_PERM_METADATA, Dataset::HOLD_PERM_FILE ].each do |hold|
    it "does not look up a sharing code when #{hold}" do
      dataset.update!(hold_state: hold)
      dataset.create_share_code!
      expect(dataset).not_to receive(:current_share_code)

      expect(dataset.has_sharing_link?).to be(false)
    end
  end

  [ Dataset::HOLD_TEMP_METADATA, Dataset::HOLD_TEMP_FILE, Dataset::HOLD_TEMP_VERSION ].each do |hold|
    it "reports an effective sharing link when #{hold}" do
      dataset.update!(hold_state: hold)
      dataset.create_share_code!

      expect(dataset.has_sharing_link?).to be(true)
    end
  end

  it "rejects missing, malformed and incorrect codes" do
    dataset.create_share_code!

    [ nil, "", [], {}, "incorrect" ].each do |code|
      expect(dataset.valid_share_code?(code: code)).to be(false)
    end
  end

  it "expires a code strictly older than one year and clears the cached association" do
    code = dataset.create_share_code!(created_at: 1.year.ago - 1.second)

    2.times { expect(dataset.current_share_code).to be_nil }
    expect(dataset.share_code).to be_nil
    expect(ShareCode.exists?(code.id)).to be(false)
    expect(dataset.has_sharing_link?).to be(false)
  end

  it "keeps a code at the exact one-year boundary" do
    travel_to Time.current.change(usec: 0) do
      code = dataset.create_share_code!(created_at: 1.year.ago)

      expect(dataset.current_share_code).to eq(code.code)
    end
  end

  it "revokes the code when the dataset is published without an embargo" do
    dataset = create(:dataset, :with_required_metadata)
    dataset.create_share_code!

    dataset.update!(publication_state: :published)

    expect(dataset.reload.share_code).to be_nil
  end

  [ Dataset::EMBARGO_FILE, Dataset::EMBARGO_METADATA ].each do |embargo|
    it "retains a code during a #{embargo} embargo and revokes it on release" do
      dataset = create(:dataset, :with_required_metadata, embargo: embargo, release_date: Date.current + 2)
      code = dataset.create_share_code!
      dataset.update!(publication_state: :published)

      expect(dataset.current_share_code).to eq(code.code)

      travel_to 3.days.from_now do
        expect(dataset.current_share_code).to be_nil
        expect(dataset.has_sharing_link?).to be(false)
        expect(ShareCode.exists?(code.id)).to be(false)
      end
    end
  end

  [ Dataset::HOLD_PERM_METADATA, Dataset::HOLD_PERM_FILE ].each do |hold|
    it "revokes the share code on save when #{hold} is applied" do
      code = dataset.create_share_code!
      dataset.update!(hold_state: hold)

      expect(ShareCode.exists?(code.id)).to be(false)
    end
  end
end
