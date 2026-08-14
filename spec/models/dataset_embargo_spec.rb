require "rails_helper"

RSpec.describe Dataset, type: :model do
  describe "external files" do
    it "returns false when both external files note and link are blank" do
      dataset = create(:dataset, external_files_note: "", external_files_link: nil)

      expect(dataset.external_files?).to be(false)
    end

    it "returns true when external files note is present" do
      dataset = create(:dataset, external_files_note: "See external repository", external_files_link: nil)

      expect(dataset.external_files?).to be(true)
    end

    it "returns true when external files link is present" do
      dataset = create(:dataset, external_files_note: "", external_files_link: "https://example.org/large-files")

      expect(dataset.external_files?).to be(true)
    end

    it "returns false when external files note and link are whitespace only" do
      dataset = create(:dataset, external_files_note: "   ", external_files_link: "   ")

      expect(dataset.external_files?).to be(false)
    end
  end

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

    it "allows draft datasets with metadata embargo and no release_date" do
      dataset = build(:dataset, publication_state: :draft, embargo: Dataset::EMBARGO_METADATA, release_date: nil)

      expect(dataset).to be_valid
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

    it "returns false for publicly_readable_now? when dataset is marked test" do
      dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_NONE, is_test: true)

      expect(dataset.publicly_readable_now?).to be(false)
    end

    it "returns false for files_publicly_readable_now? when dataset is marked test" do
      dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_NONE, is_test: true)

      expect(dataset.files_publicly_readable_now?).to be(false)
    end

    it "returns false for publicly_readable_now? when metadata is temporarily suppressed by hold" do
      dataset = create(:dataset, :published, :hold_temp_metadata, embargo: Dataset::EMBARGO_NONE)

      expect(dataset.publicly_readable_now?).to be(false)
    end

    it "returns true for publicly_readable_now? when files are temporarily suppressed by hold" do
      dataset = create(:dataset, :published, :hold_temp_file, embargo: Dataset::EMBARGO_NONE)

      expect(dataset.publicly_readable_now?).to be(true)
    end

    it "returns false for files_publicly_readable_now? when files are temporarily suppressed by hold" do
      dataset = create(:dataset, :published, :hold_temp_file, embargo: Dataset::EMBARGO_NONE)

      expect(dataset.files_publicly_readable_now?).to be(false)
    end

    it "returns false for publicly_readable_now? when version candidate hold is set" do
      dataset = create(:dataset, :published, :hold_temp_version, embargo: Dataset::EMBARGO_NONE)

      expect(dataset.publicly_readable_now?).to be(false)
    end

    it "returns false for files_publicly_readable_now? when version candidate hold is set" do
      dataset = create(:dataset, :published, :hold_temp_version, embargo: Dataset::EMBARGO_NONE)

      expect(dataset.files_publicly_readable_now?).to be(false)
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
      test_dataset = create(:dataset, :published,
        title: "Test Dataset",
        embargo: Dataset::EMBARGO_NONE,
        release_date: nil,
        is_test: true
      )

      scope_ids = Dataset.publicly_readable_now.pluck(:id)

      expect(scope_ids).to include(released_metadata.id)
      expect(scope_ids).to include(public_none.id)
      expect(scope_ids).not_to include(unreleased_metadata.id)
      expect(scope_ids).not_to include(draft_dataset.id)
      expect(scope_ids).not_to include(test_dataset.id)
    end

    it "scope publicly_readable_now excludes metadata-suppressed and version-hold datasets" do
      public_none = create(:dataset, :published,
        title: "Public None Hold",
        embargo: Dataset::EMBARGO_NONE,
        hold_state: Dataset::HOLD_NONE
      )
      metadata_suppressed = create(:dataset, :published,
        title: "Metadata Suppressed",
        embargo: Dataset::EMBARGO_NONE,
        hold_state: Dataset::HOLD_TEMP_METADATA
      )
      version_hold = create(:dataset, :published,
        title: "Version Hold",
        embargo: Dataset::EMBARGO_NONE,
        hold_state: Dataset::HOLD_TEMP_VERSION
      )

      scope_ids = Dataset.publicly_readable_now.pluck(:id)

      expect(scope_ids).to include(public_none.id)
      expect(scope_ids).not_to include(metadata_suppressed.id)
      expect(scope_ids).not_to include(version_hold.id)
    end

    it "scope files_publicly_readable_now_scope excludes file-suppressed datasets" do
      public_none = create(:dataset, :published,
        title: "Files Public None Hold",
        embargo: Dataset::EMBARGO_NONE,
        hold_state: Dataset::HOLD_NONE
      )
      file_suppressed = create(:dataset, :published,
        title: "Files Suppressed",
        embargo: Dataset::EMBARGO_NONE,
        hold_state: Dataset::HOLD_TEMP_FILE
      )

      scope_ids = Dataset.files_publicly_readable_now_scope.pluck(:id)

      expect(scope_ids).to include(public_none.id)
      expect(scope_ids).not_to include(file_suppressed.id)
    end

    it "adds release date publish requirement when file embargo is set without release date" do
      dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_NONE, release_date: nil)
      dataset.update_columns(embargo: Dataset::EMBARGO_FILE, release_date: nil)
      dataset.reload

      expect(dataset.missing_publish_fields).to include("release date when embargo is file or metadata")
      expect(dataset.ready_to_publish?).to be(false)
    end

    it "allows publish readiness when file embargo has a release date" do
      dataset = create(:dataset, :published,
        embargo: Dataset::EMBARGO_FILE,
        release_date: Date.current + 7
      )

      expect(dataset.missing_publish_fields).not_to include("release date when embargo is file or metadata")
      expect(dataset.ready_to_publish?).to be(true)
    end
  end
end
