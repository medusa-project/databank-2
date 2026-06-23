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
end
