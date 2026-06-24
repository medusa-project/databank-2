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
      "hold_state" => "none",
      "release_date" => "2020-01-10",
      "embargo" => "metadata embargo",
      "is_test" => true,
      "is_import" => true,
      "dataset_version" => "V3",
      "tombstone_date" => "2024-12-25",
      "nested_updated_at" => "2020-01-03T00:00:00Z",
      "created_at" => "2020-01-01T00:00:00Z",
      "updated_at" => "2020-01-02T00:00:00Z",
      "creators" => [
        {
          "given_name" => "Ada",
          "family_name" => "Lovelace",
          "identifier" => "0000-0001-2345-6789",
          "identifier_scheme" => "ORCID",
          "is_contact" => true,
          "row_position" => 1
        }
      ],
      "contributors" => [
        {
          "given_name" => "Grace",
          "family_name" => "Hopper",
          "identifier" => "https://ror.org/03yrm5c26",
          "identifier_scheme" => "ROR",
          "position" => 1
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
          "selected_type" => "Article",
          "material_type" => "Article",
          "citation" => "Citation text",
          "note" => "Curator-only migration note",
          "link" => "https://doi.org/10.1000/xyz",
          "uri" => "https://doi.org/10.1000/xyz",
          "uri_type" => "DOI",
          "datacite_list" => "IsSupplementTo,IsCitedBy"
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
      ],
      "notes" => [
        {
          "body" => "Imported sample note",
          "author" => "sample-curator@example.edu"
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
    expect(dataset.legacy_publication_state).to eq("released")
    expect(dataset.hold_state).to eq("none")
    expect(dataset.release_date).to eq(Date.new(2020, 1, 10))
    expect(dataset.published_at).to eq(Time.zone.parse("2020-01-02T00:00:00Z"))
    expect(dataset.embargo).to eq(Dataset::EMBARGO_METADATA)
    expect(dataset.is_test).to be(true)
    expect(dataset.is_import).to be(true)
    expect(dataset.dataset_version).to eq("V3")
    expect(dataset.tombstone_date).to eq(Date.new(2024, 12, 25))
    expect(dataset.nested_updated_at).to eq(Time.zone.parse("2020-01-03T00:00:00Z"))
    expect(dataset.creators.count).to eq(1)
    expect(dataset.contributors.count).to eq(1)
    expect(dataset.creators.first.identifier_scheme).to eq("ORCID")
    expect(dataset.contributors.first.identifier_scheme).to eq("ROR")
    expect(dataset.funders.count).to eq(1)
    expect(dataset.related_materials.count).to eq(1)
    expect(dataset.datafiles.count).to eq(1)
    expect(dataset.notes.count).to eq(1)
    expect(dataset.notes.first.body).to eq("Imported sample note")
    datafile = dataset.datafiles.first
    expect(datafile.storage_root).to eq("medusa")
    expect(datafile.storage_key).to eq("DOI-10-13012-b2idb-9099901_v1/dataset_files/file.csv")
    expect(datafile.medusa_id).to eq("medusa-abc12")
    material = dataset.related_materials.first
    expect(material.relation_types).to eq([ "IsSupplementTo", "IsCitedBy" ])
    expect(material.related_material_relationships.count).to eq(2)
    expect(material.selected_type).to eq("Article")
    expect(material.note).to eq("Curator-only migration note")
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

  it "maps legacy organization names into institution_name for creators and contributors" do
    payload = {
      "title" => "Institution Name Mapping",
      "identifier" => "10.13012/B2IDB-9099902_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-9099902.json",
      "publication_state" => "released",
      "creators" => [
        {
          "name" => "University Library",
          "row_position" => 1
        }
      ],
      "contributors" => [
        {
          "name" => "Research Data Service",
          "position" => 1
        }
      ]
    }

    File.write(datasets_dir.join("dataset.json"), JSON.pretty_generate(payload))

    summary = described_class.new(input_dir: run_dir.to_s).call

    expect(summary[:created]).to eq(1)
    expect(summary[:failed]).to eq(0)

    dataset = Dataset.find_by!(identifier: "10.13012/B2IDB-9099902_V1")
    creator = dataset.creators.first
    contributor = dataset.contributors.first

    expect(creator.institution_name).to eq("University Library")
    expect(creator.name).to eq("University Library")
    expect(contributor.institution_name).to eq("Research Data Service")
    expect(contributor.name).to eq("Research Data Service")
  end

  it "maps legacy embargo publication state as published and preserves embargo semantics" do
    payload = {
      "title" => "Embargo Publication State Mapping",
      "identifier" => "10.13012/B2IDB-9099903_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-9099903.json",
      "publication_state" => "metadata embargo",
      "release_date" => "2026-08-01",
      "updated_at" => "2026-06-01T00:00:00Z"
    }

    File.write(datasets_dir.join("dataset.json"), JSON.pretty_generate(payload))

    summary = described_class.new(input_dir: run_dir.to_s).call

    expect(summary[:created]).to eq(1)
    expect(summary[:failed]).to eq(0)

    dataset = Dataset.find_by!(identifier: "10.13012/B2IDB-9099903_V1")
    expect(dataset.legacy_publication_state).to eq("metadata embargo")
    expect(dataset.publication_state).to eq("published")
    expect(dataset.embargo).to eq(Dataset::EMBARGO_METADATA)
    expect(dataset.release_date).to eq(Date.new(2026, 8, 1))
  end
end
