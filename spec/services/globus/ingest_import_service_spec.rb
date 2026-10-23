require "rails_helper"

RSpec.describe Globus::IngestImportService, type: :service do
  let!(:dataset) do
    Dataset.create!(
      key: "IDB-1111111",
      title: "Globus Ingest Dataset",
      description: "Dataset for ingest import",
      owner_uid: "owner-ingest",
      depositor_name: "Owner Ingest",
      depositor_email: "owner-ingest@example.edu"
    )
  end

  let(:ingest_root) { instance_double("MedusaStorage::Root") }
  let(:draft_root) { instance_double("MedusaStorage::Root", name: "draft") }

  before do
    allow(StorageManager.instance).to receive(:globus_ingest_root).and_return(ingest_root)
    allow(StorageManager.instance).to receive(:draft_root).and_return(draft_root)
  end

  it "recognizes matching ingest and draft storage configurations regardless of root name" do
    config = { type: "s3", bucket: "test-bucket", prefix: "uploads/" }
    stub_const("STORAGE_CONFIG", storage: [ config.merge(name: "draft"), config.merge(name: "globus_ingest") ])

    expect(StorageManager.instance.globus_ingest_uses_draft_storage?).to be true
  end

  it "distinguishes roots with different prefixes in the same bucket" do
    stub_const("STORAGE_CONFIG", storage: [
      { name: "draft", type: "s3", bucket: "test-bucket", prefix: "uploads/" },
      { name: "globus_ingest", type: "s3", bucket: "test-bucket", prefix: "ingest/" }
    ])

    expect(StorageManager.instance.globus_ingest_uses_draft_storage?).to be false
  end

  it "creates Datafile records from ingest keys using dataset-key directory convention" do
    allow(ingest_root).to receive(:exist?).with("IDB-1111111/").and_return(true)
    allow(ingest_root).to receive(:file_keys).with("IDB-1111111").and_return([ "IDB-1111111/notes.csv" ])
    allow(ingest_root).to receive(:size).with("IDB-1111111/notes.csv").and_return(123)

    result = described_class.new(dataset_key: dataset.key).call

    expect(result[:created]).to eq(1)
    expect(result[:failed]).to eq(0)

    datafile = dataset.datafiles.find_by!(binary_name: "notes.csv")
    expect(datafile.storage_root).to eq("draft")
    expect(datafile.storage_key).to eq("IDB-1111111/notes.csv")
    expect(datafile.binary_size).to eq(123)
  end

  it "is idempotent when a datafile already exists by binary_name" do
    dataset.datafiles.create!(
      web_id: "abcde",
      binary_name: "notes.csv",
      binary_size: 123,
      storage_root: "draft",
      storage_key: "IDB-1111111/notes.csv"
    )

    allow(ingest_root).to receive(:exist?).with("IDB-1111111/").and_return(true)
    allow(ingest_root).to receive(:file_keys).with("IDB-1111111").and_return([ "IDB-1111111/notes.csv" ])

    result = described_class.new(dataset_key: dataset.key).call

    expect(result[:created]).to eq(0)
    expect(result[:skipped_existing]).to eq(1)
    expect(dataset.datafiles.where(binary_name: "notes.csv").count).to eq(1)
  end

  it "reports would_create entries in dry-run mode without creating records" do
    allow(ingest_root).to receive(:exist?).with("IDB-1111111/").and_return(true)
    allow(ingest_root).to receive(:file_keys).with("IDB-1111111").and_return([ "IDB-1111111/new.csv" ])
    allow(ingest_root).to receive(:size).with("IDB-1111111/new.csv").and_return(44)

    result = described_class.new(dataset_key: dataset.key, dry_run: true).call

    expect(result[:created]).to eq(1)
    expect(result[:records].last[:status]).to eq(:would_create)
    expect(dataset.datafiles.find_by(binary_name: "new.csv")).to be_nil
  end

  it "copies into draft storage when ingest and draft roots are different" do
    allow(StorageManager.instance).to receive(:globus_ingest_uses_draft_storage?).and_return(false)
    allow(ingest_root).to receive(:exist?).and_return(true)
    allow(ingest_root).to receive(:file_keys).and_return([ "#{dataset.key}/notes.csv" ])
    allow(ingest_root).to receive(:size).and_return(123)
    expect(draft_root).to receive(:copy_content_to).with("#{dataset.key}/notes.csv", ingest_root, "#{dataset.key}/notes.csv")

    expect(described_class.new(dataset_key: dataset.key).call[:created]).to eq(1)
  end

  it "supports curator maintenance imports into published datasets and clears stale readiness flags" do
    dataset.update!(publication_state: :published, all_globus: true, all_medusa: true)
    allow(ingest_root).to receive(:exist?).and_return(true)
    allow(ingest_root).to receive(:file_keys).and_return([ "#{dataset.key}/notes.csv" ])
    allow(ingest_root).to receive(:size).and_return(123)

    expect(described_class.new(dataset_key: dataset.key).call[:created]).to eq(1)
    expect(dataset.reload.all_globus).to be false
    expect(dataset.all_medusa).to be false
  end

  it "reports and logs storage failures without creating a record" do
    logger = instance_double(Logger, warn: nil)
    allow(ingest_root).to receive(:exist?).and_return(true)
    allow(ingest_root).to receive(:file_keys).and_return([ "#{dataset.key}/notes.csv" ])
    allow(ingest_root).to receive(:size).and_raise(IOError, "unavailable")

    result = described_class.new(dataset_key: dataset.key, logger: logger).call

    expect(result[:failed]).to eq(1)
    expect(result[:created]).to eq(0)
    expect(logger).to have_received(:warn).with(/unavailable/)
  end

  it "imports files from S3 prefixes that do not have a directory marker" do
    allow(ingest_root).to receive(:exist?).and_return(false)
    allow(ingest_root).to receive(:root_type).and_return(:s3)
    allow(ingest_root).to receive(:file_keys).and_return([ "#{dataset.key}/notes.csv" ])
    allow(ingest_root).to receive(:size).and_return(123)

    expect(described_class.new(dataset_key: dataset.key).call[:created]).to eq(1)
  end

  it "does not create records when copying from a separate ingest location fails" do
    allow(StorageManager.instance).to receive(:globus_ingest_uses_draft_storage?).and_return(false)
    allow(ingest_root).to receive(:exist?).and_return(true)
    allow(ingest_root).to receive(:file_keys).and_return([ "#{dataset.key}/notes.csv" ])
    allow(ingest_root).to receive(:size).and_return(123)
    allow(draft_root).to receive(:copy_content_to).and_raise(IOError, "copy failed")

    result = described_class.new(dataset_key: dataset.key).call

    expect(result.values_at(:created, :failed)).to eq([ 0, 1 ])
    expect(dataset.datafiles).to be_empty
  end

  it "preserves readable file bytes when ingest and draft use different locations" do
    Dir.mktmpdir("globus-import-spec-") do |directory|
      ingest_path = File.join(directory, "ingest")
      draft_path = File.join(directory, "draft")
      FileUtils.mkdir_p([ ingest_path, draft_path ])
      source = MedusaStorage::Root::Filesystem.new(name: "globus_ingest", path: ingest_path)
      destination = MedusaStorage::Root::Filesystem.new(name: "draft", path: draft_path)
      source.write_string_to("#{dataset.key}/notes.csv", "a,b\n1,2\n")
      allow(StorageManager.instance).to receive(:globus_ingest_root).and_return(source)
      allow(StorageManager.instance).to receive(:draft_root).and_return(destination)
      allow(StorageManager.instance).to receive(:globus_ingest_uses_draft_storage?).and_return(false)
      allow(StorageManager.instance.root_set).to receive(:at).with("draft").and_return(destination)

      expect(described_class.new(dataset_key: dataset.key).call[:created]).to eq(1)

      imported = dataset.datafiles.find_by!(binary_name: "notes.csv")
      imported.with_input_io { |io| expect(io.read).to eq("a,b\n1,2\n") }
    end
  end
end
