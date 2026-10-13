require "rails_helper"

RSpec.describe Medusa::FinalizeIngestService, type: :service do
  let!(:dataset) do
    Dataset.create!(
      key: "IDB-4444444",
      title: "Finalize Ingest Dataset",
      description: "Dataset for medusa finalize ingest",
      owner_uid: "owner-finalize",
      depositor_name: "Owner Finalize",
      depositor_email: "owner-finalize@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE
    )
  end

  let!(:datafile) do
    dataset.datafiles.create!(
      web_id: "pqrst",
      binary_name: "analysis.csv",
      binary_size: 256,
      storage_root: "draft",
      storage_key: "IDB-4444444/analysis.csv"
    )
  end

  let(:root_set) { instance_double("MedusaStorage::RootSet") }
  let(:draft_root) { instance_double("MedusaStorage::Root", name: "draft") }
  let(:medusa_root) { instance_double("MedusaStorage::Root", name: "medusa") }

  before do
    allow(StorageManager.instance).to receive(:root_set).and_return(root_set)
    allow(root_set).to receive(:at).with("draft").and_return(draft_root)
    allow(StorageManager.instance).to receive(:medusa_root).and_return(medusa_root)
  end

  it "switches storage_root to medusa and deletes the draft copy when sizes match" do
    allow(medusa_root).to receive(:exist?).with("IDB-4444444/analysis.csv").and_return(true)
    allow(draft_root).to receive(:exist?).with("IDB-4444444/analysis.csv").and_return(true)
    allow(draft_root).to receive(:size).with("IDB-4444444/analysis.csv").and_return(256)
    allow(medusa_root).to receive(:size).with("IDB-4444444/analysis.csv").and_return(256)
    allow(draft_root).to receive(:delete_content)

    result = described_class.new(dataset).call

    expect(result).to be true
    expect(draft_root).to have_received(:delete_content).with("IDB-4444444/analysis.csv")
    datafile.reload
    expect(datafile.storage_root).to eq("medusa")
    expect(datafile.storage_key).to eq("IDB-4444444/analysis.csv")
    expect(dataset.reload.all_medusa).to be true
  end

  it "leaves the datafile alone when it is not yet present in the medusa root" do
    allow(medusa_root).to receive(:exist?).with("IDB-4444444/analysis.csv").and_return(false)

    result = described_class.new(dataset).call

    expect(result).to be false
    expect(datafile.reload.storage_root).to eq("draft")
    expect(dataset.reload.all_medusa).to be false
  end

  it "does not switch storage_root when draft and medusa sizes differ" do
    allow(medusa_root).to receive(:exist?).with("IDB-4444444/analysis.csv").and_return(true)
    allow(draft_root).to receive(:exist?).with("IDB-4444444/analysis.csv").and_return(true)
    allow(draft_root).to receive(:size).with("IDB-4444444/analysis.csv").and_return(256)
    allow(medusa_root).to receive(:size).with("IDB-4444444/analysis.csv").and_return(128)

    result = described_class.new(dataset).call

    expect(result).to be false
    expect(datafile.reload.storage_root).to eq("draft")
    expect(dataset.reload.all_medusa).to be false
  end

  it "does not mark all_medusa true when another datafile is missing from medusa" do
    dataset.datafiles.create!(
      web_id: "uvwxy",
      binary_name: "other.csv",
      binary_size: 32,
      storage_root: "draft",
      storage_key: "IDB-4444444/other.csv"
    )
    allow(medusa_root).to receive(:exist?).with("IDB-4444444/analysis.csv").and_return(true)
    allow(medusa_root).to receive(:exist?).with("IDB-4444444/other.csv").and_return(false)
    allow(draft_root).to receive(:exist?).with("IDB-4444444/analysis.csv").and_return(true)
    allow(draft_root).to receive(:size).with("IDB-4444444/analysis.csv").and_return(256)
    allow(medusa_root).to receive(:size).with("IDB-4444444/analysis.csv").and_return(256)
    allow(draft_root).to receive(:delete_content)

    result = described_class.new(dataset).call

    expect(result).to be false
    expect(dataset.reload.all_medusa).to be false
  end
end
