require "rails_helper"

RSpec.describe Dataset, type: :model do
  describe "embargo behavior" do
    it "normalizes blank embargo to none" do
      dataset = create(:dataset, :published, embargo: nil)

      expect(dataset.embargo).to eq(Dataset::EMBARGO_NONE)
      expect(dataset.embargo_mode).to eq(Dataset::EMBARGO_NONE)
    end

    it "requires release_date when embargo is file" do
      dataset = build(:dataset, :published, embargo: Dataset::EMBARGO_FILE, release_date: nil)

      expect(dataset).not_to be_valid
      expect(dataset.errors[:release_date]).to include("is required when embargo is file or metadata")
    end

    it "requires release_date when embargo is metadata" do
      dataset = build(:dataset, :published, embargo: Dataset::EMBARGO_METADATA, release_date: nil)

      expect(dataset).not_to be_valid
      expect(dataset.errors[:release_date]).to include("is required when embargo is file or metadata")
    end

    it "allows none embargo without release_date" do
      dataset = build(:dataset, :published, embargo: Dataset::EMBARGO_NONE, release_date: nil)

      expect(dataset).to be_valid
    end

    it "returns false for publicly_readable_now? when not published" do
      dataset = create(:dataset, publication_state: :draft, embargo: Dataset::EMBARGO_NONE)

      expect(dataset.publicly_readable_now?).to be(false)
    end

    it "returns false for publicly_readable_now? when metadata embargo is not released" do
      dataset = create(:dataset, :published, :embargo_metadata_unreleased)

      expect(dataset.publicly_readable_now?).to be(false)
    end

    it "returns true for publicly_readable_now? when metadata embargo is released" do
      dataset = create(:dataset, :published, :embargo_metadata_released)

      expect(dataset.publicly_readable_now?).to be(true)
    end

    it "returns false for files_publicly_readable_now? when file embargo is not released" do
      dataset = create(:dataset, :published, :embargo_file_unreleased)

      expect(dataset.files_publicly_readable_now?).to be(false)
    end

    it "returns false for files_publicly_readable_now? when metadata embargo is not released" do
      dataset = create(:dataset, :published, :embargo_metadata_unreleased)

      expect(dataset.files_publicly_readable_now?).to be(false)
    end

    it "returns true for files_publicly_readable_now? when metadata embargo is released" do
      dataset = create(:dataset, :published, :embargo_metadata_released)

      expect(dataset.files_publicly_readable_now?).to be(true)
    end

    it "scope publicly_readable_now includes released metadata embargo and excludes unreleased metadata embargo" do
      released_metadata = create(:dataset, :published,
        title: "Released Metadata",
        embargo: Dataset::EMBARGO_METADATA,
        release_date: Date.current - 1
      )
      unreleased_metadata = create(:dataset, :published,
        title: "Unreleased Metadata",
        embargo: Dataset::EMBARGO_METADATA,
        release_date: Date.current + 1
      )
      public_none = create(:dataset, :published,
        title: "No Embargo",
        embargo: Dataset::EMBARGO_NONE,
        release_date: nil
      )
      draft_dataset = create(:dataset,
        title: "Draft",
        publication_state: :draft,
        embargo: Dataset::EMBARGO_NONE
      )

      scope_ids = Dataset.publicly_readable_now.pluck(:id)

      expect(scope_ids).to include(released_metadata.id)
      expect(scope_ids).to include(public_none.id)
      expect(scope_ids).not_to include(unreleased_metadata.id)
      expect(scope_ids).not_to include(draft_dataset.id)
    end
  end
end
