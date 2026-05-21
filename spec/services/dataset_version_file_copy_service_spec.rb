require "rails_helper"

RSpec.describe DatasetVersionFileCopyService do
  describe "#call" do
    it "copies attached and storage-backed files from previous version dataset" do
      previous = Dataset.create!(
        title: "Previous Dataset",
        description: "v1",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner",
        depositor_email: "owner@example.edu",
        publication_state: :published,
        identifier: "10.5555/IDB-1010101"
      )

      attached_source = previous.datafiles.create!(description: "Attached source")
      attached_source.binary.attach(
        io: StringIO.new("a,b\n1,2\n"),
        filename: "source.csv",
        content_type: "text/csv"
      )
      attached_source.sync_metadata_from_attachment!
      attached_source.save!

      previous.datafiles.create!(
        binary_name: "remote.csv",
        binary_size: 123,
        description: "Storage source",
        storage_root: "medusa",
        storage_key: "path/to/remote.csv",
        medusa_id: "m-123"
      )

      version = Dataset.create!(
        title: "New Version",
        description: "v2",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner",
        depositor_email: "owner@example.edu",
        publication_state: :draft
      )
      version.related_materials.create!(
        title: previous.title,
        uri: "https://doi.org/#{previous.identifier}",
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )

      result = described_class.new(version_dataset: version).call

      expect(result.copied_count).to eq(2)
      expect(result.skipped_count).to eq(0)

      copied_attached = version.datafiles.find_by!(binary_name: "source.csv")
      expect(copied_attached.binary).to be_attached
      expect(copied_attached.binary.blob_id).to eq(attached_source.binary.blob_id)

      copied_storage = version.datafiles.find_by!(storage_key: "path/to/remote.csv")
      expect(copied_storage.binary).not_to be_attached
      expect(copied_storage.binary_name).to eq("remote.csv")
      expect(copied_storage.binary_size).to eq(123)
    end

    it "is idempotent and skips duplicates when run repeatedly" do
      previous = Dataset.create!(
        title: "Previous Dataset",
        description: "v1",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner",
        depositor_email: "owner@example.edu",
        publication_state: :published,
        identifier: "10.5555/IDB-2020202"
      )
      source = previous.datafiles.create!(binary_name: "remote.csv", binary_size: 10, storage_root: "medusa", storage_key: "path/to/remote.csv")

      version = Dataset.create!(
        title: "New Version",
        description: "v2",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner",
        depositor_email: "owner@example.edu",
        publication_state: :draft
      )
      version.related_materials.create!(
        title: previous.title,
        uri: "https://doi.org/#{previous.identifier}",
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )

      first = described_class.new(version_dataset: version).call
      second = described_class.new(version_dataset: version).call

      expect(source).to be_present
      expect(first.copied_count).to eq(1)
      expect(first.skipped_count).to eq(0)
      expect(second.copied_count).to eq(0)
      expect(second.skipped_count).to eq(1)
      expect(version.datafiles.count).to eq(1)
    end

    it "raises when previous version dataset cannot be resolved" do
      version = Dataset.create!(
        title: "New Version",
        description: "v2",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner",
        depositor_email: "owner@example.edu",
        publication_state: :draft
      )

      expect {
        described_class.new(version_dataset: version).call
      }.to raise_error(ArgumentError, "previous version dataset not found")
    end
  end
end
