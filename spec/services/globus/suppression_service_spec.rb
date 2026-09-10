require "rails_helper"

RSpec.describe Globus::SuppressionService, type: :service do
  let!(:dataset) do
    Dataset.create!(
      key: "IDB-3333333",
      title: "Suppression Dataset",
      description: "Dataset for globus suppression",
      owner_uid: "owner-suppress",
      depositor_name: "Owner Suppress",
      depositor_email: "owner-suppress@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE,
      all_globus: true
    )
  end

  let!(:datafile) do
    dataset.datafiles.create!(
      web_id: "klmno",
      binary_name: "analysis.csv",
      binary_size: 256,
      storage_root: "draft",
      storage_key: "IDB-3333333/analysis.csv"
    )
  end

  let(:download_root) { instance_double("MedusaStorage::Root") }

  before do
    allow(StorageManager.instance).to receive(:globus_download_root).and_return(download_root)
  end

  it "removes files from the download root and clears all_globus" do
    allow(download_root).to receive(:exist?).with("IDB-3333333/analysis.csv").and_return(true)
    allow(download_root).to receive(:delete_content)

    result = described_class.new(dataset).remove_from_public_download

    expect(result).to be true
    expect(download_root).to have_received(:delete_content).with("IDB-3333333/analysis.csv")
    expect(dataset.reload.all_globus).to be false
  end

  it "returns false and logs a warning when removal fails" do
    logger = instance_double(Logger, warn: nil)
    allow(download_root).to receive(:exist?).and_raise(StandardError, "boom")

    result = described_class.new(dataset, logger: logger).remove_from_public_download

    expect(result).to be false
    expect(logger).to have_received(:warn)
    expect(dataset.reload.all_globus).to be true
  end
end
