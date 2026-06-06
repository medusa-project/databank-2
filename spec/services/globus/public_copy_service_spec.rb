require "rails_helper"

RSpec.describe Globus::PublicCopyService, type: :service do
  let!(:dataset) do
    Dataset.create!(
      key: "IDB-2222222",
      title: "Public Copy Dataset",
      description: "Dataset for public copy",
      owner_uid: "owner-copy",
      depositor_name: "Owner Copy",
      depositor_email: "owner-copy@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE
    )
  end

  let!(:datafile) do
    dataset.datafiles.create!(
      web_id: "bcdef",
      binary_name: "analysis.csv",
      binary_size: 256,
      storage_root: "draft",
      storage_key: "IDB-2222222/analysis.csv"
    )
  end

  let(:root_set) { instance_double("MedusaStorage::RootSet") }
  let(:source_root) { instance_double("MedusaStorage::Root") }
  let(:download_root) { instance_double("MedusaStorage::Root") }

  before do
    allow(StorageManager.instance).to receive(:root_set).and_return(root_set)
    allow(root_set).to receive(:at).with("draft").and_return(source_root)
    allow(StorageManager.instance).to receive(:globus_download_root).and_return(download_root)
    allow(download_root).to receive(:copy_content_to)
  end

  it "copies public files to the globus download root as <dataset_key>/<binary_name>" do
    allow(download_root).to receive(:exist?).with("IDB-2222222/analysis.csv").and_return(false)

    result = described_class.new.call

    expect(result[:copied]).to eq(1)
    expect(result[:failed]).to eq(0)
    expect(download_root).to have_received(:copy_content_to).with(
      "IDB-2222222/analysis.csv",
      source_root,
      "IDB-2222222/analysis.csv"
    )
  end

  it "is idempotent when the destination key already exists" do
    allow(download_root).to receive(:exist?).with("IDB-2222222/analysis.csv").and_return(true)

    result = described_class.new.call

    expect(result[:copied]).to eq(0)
    expect(result[:skipped_existing]).to eq(1)
    expect(download_root).not_to have_received(:copy_content_to)
  end

  it "skips non-public datasets" do
    dataset.update!(embargo: Dataset::EMBARGO_FILE, release_date: 1.day.from_now.to_date)

    result = described_class.new.call

    expect(result[:copied]).to eq(0)
    expect(result[:skipped_non_public]).to eq(1)
    expect(download_root).not_to have_received(:copy_content_to)
  end

  it "reports would_copy in dry-run mode" do
    allow(download_root).to receive(:exist?).with("IDB-2222222/analysis.csv").and_return(false)

    result = described_class.new(dry_run: true).call

    expect(result[:copied]).to eq(1)
    expect(result[:records].last[:status]).to eq(:would_copy)
    expect(download_root).not_to have_received(:copy_content_to)
  end
end
