require "rails_helper"

RSpec.describe Migration::SampleImportService do
  let(:tmp_root) { Rails.root.join("tmp", "spec_migration_samples") }
  let(:run_dir) { tmp_root.join("run1") }
  let(:datasets_dir) { run_dir.join("datasets") }

  before do
    FileUtils.rm_rf(tmp_root)
    FileUtils.mkdir_p(datasets_dir)
  end

  after do
    FileUtils.rm_rf(tmp_root)
  end

  it "imports payloads and creates dataset with nested records" do
    payload = {
      "title" => "Sample Dataset",
      "identifier" => "10.13012/B2IDB-9099901_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-9099901.json",
      "description" => "desc",
      "publication_state" => "released",
      "created_at" => "2020-01-01T00:00:00Z",
      "updated_at" => "2020-01-02T00:00:00Z",
      "creators" => [
        {
          "given_name" => "Ada",
          "family_name" => "Lovelace",
          "is_contact" => true,
          "row_position" => 1
        }
      ],
      "funders" => [
        {
          "name" => "Example Funder",
          "identifier" => "10.1234/funder",
          "grant" => "ABC-123"
        }
      ],
      "related_materials" => [
        {
          "material_type" => "Article",
          "citation" => "Citation text",
          "link" => "https://doi.org/10.1000/xyz"
        }
      ],
      "datafiles" => [
        {
          "web_id" => "abc12",
          "medusa_id" => "medusa-abc12",
          "binary_name" => "file.csv",
          "binary_size" => 10,
          "storage_root" => "medusa",
          "storage_key" => "DOI-10-13012-b2idb-9099901_v1/dataset_files/file.csv"
        }
      ]
    }

    File.write(datasets_dir.join("dataset.json"), JSON.pretty_generate(payload))

    summary = described_class.new(input_dir: run_dir.to_s).call

    expect(summary[:created]).to eq(1)
    expect(summary[:failed]).to eq(0)

    dataset = Dataset.find_by!(identifier: "10.13012/B2IDB-9099901_V1")
    expect(dataset.key).to eq("IDB-9099901")
    expect(dataset.publication_state).to eq("published")
    expect(dataset.creators.count).to eq(1)
    expect(dataset.funders.count).to eq(1)
    expect(dataset.related_materials.count).to eq(1)
    expect(dataset.datafiles.count).to eq(1)
    datafile = dataset.datafiles.first
    expect(datafile.storage_root).to eq("medusa")
    expect(datafile.storage_key).to eq("DOI-10-13012-b2idb-9099901_v1/dataset_files/file.csv")
    expect(datafile.medusa_id).to eq("medusa-abc12")
  end

  it "skips existing by default and updates in overwrite mode" do
    Dataset.create!(
      key: "IDB-7654321",
      identifier: "10.13012/B2IDB-7654321_V1",
      title: "Original",
      owner_uid: "owner",
      depositor_name: "Owner",
      depositor_email: "owner@example.edu"
    )

    payload = {
      "title" => "Updated Title",
      "identifier" => "10.13012/B2IDB-7654321_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-7654321.json"
    }

    File.write(datasets_dir.join("dataset.json"), JSON.pretty_generate(payload))

    summary_skip = described_class.new(input_dir: run_dir.to_s).call
    expect(summary_skip[:skipped_existing]).to eq(1)
    expect(Dataset.find_by!(identifier: payload["identifier"]).title).to eq("Original")

    summary_overwrite = described_class.new(input_dir: run_dir.to_s, overwrite: true).call
    expect(summary_overwrite[:updated]).to eq(1)
    expect(Dataset.find_by!(identifier: payload["identifier"]).title).to eq("Updated Title")
  end
end
