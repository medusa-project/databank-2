require "rails_helper"

RSpec.describe Migration::FlatBundleImportService do
  let(:bundle_path) { Rails.root.join("tmp", "spec_flat_migration_bundle.ndjson") }
  let(:checksum_path) { Rails.root.join("tmp", "spec_flat_migration_bundle.ndjson.sha256") }

  after do
    FileUtils.rm_f(bundle_path)
    FileUtils.rm_f(checksum_path)
  end

  it "imports dataset, datafile, and nested items from flat records" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    nested_item_id = SecureRandom.random_number(900_000) + 100_000

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Flat Bundle Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "released",
        embargo: "none",
        creators: [
          {
            given_name: "Alex",
            family_name: "Example",
            email: "alex@example.edu",
            row_position: 0,
            is_contact: true
          }
        ],
        funders: [
          {
            name: "National Science Foundation",
            grant: "NSF-123"
          }
        ],
        related_materials: [
          {
            uri: "https://doi.org/10.1000/example",
            datacite_list: "IsSupplementTo"
          }
        ]
      },
      {
        type: "datafile",
        dataset_id: dataset_key,
        datafile_id: "ab123",
        binary_name: "results.csv",
        binary_size: 321,
        storage_root: "draft",
        storage_key: "flat/results.csv",
        peek_type: "code"
      },
      {
        type: "nested_item",
        dataset_id: dataset_key,
        datafile_id: "ab123",
        item_id: "ni-#{nested_item_id}",
        parent_item_id: nil,
        item_name: "results.csv",
        media_type: "text/csv",
        size: 321,
        item_path: "results.csv",
        is_directory: false
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:validation_error]).to be_nil
    expect(summary[:created]).to eq(1)
    expect(summary[:failed]).to eq(0)
    expect(summary[:record_counts]).to eq(datasets: 1, datafiles: 1, nested_items: 1)

    dataset = Dataset.find_by!(key: dataset_key)
    expect(dataset.owner_uid).to eq("legacy-owner")
    expect(dataset).to be_published

    creator = dataset.creators.first
    expect(creator.position).to eq(1)
    expect(creator.row_position).to eq(1)

    funder = dataset.funders.first
    expect(funder.position).to eq(1)
    expect(funder.row_position).to eq(1)

    related_material = dataset.related_materials.first
    expect(related_material.position).to eq(1)
    expect(related_material.row_position).to eq(1)

    datafile = dataset.datafiles.find_by!(web_id: "ab123")
    expect(datafile.binary_name).to eq("results.csv")
    expect(datafile.nested_items.pluck(:id)).to include(nested_item_id)
  end

  it "supports dry-run mode without writing database records" do
    records = [
      {
        type: "dataset",
        dataset_id: "IDB-5252525",
        title: "Dry Run Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft"
      },
      {
        type: "datafile",
        dataset_id: "IDB-5252525",
        datafile_id: "cd456",
        binary_name: "data.txt"
      },
      {
        type: "nested_item",
        dataset_id: "IDB-5252525",
        datafile_id: "cd456",
        item_id: "ni-9002",
        item_name: "data.txt",
        media_type: "text/plain",
        size: 10,
        item_path: "data.txt",
        is_directory: false
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s, dry_run: true).call

    expect(summary[:failed]).to eq(0)
    expect(summary[:record_counts]).to eq(datasets: 1, datafiles: 1, nested_items: 1)
    expect(Dataset.find_by(key: "IDB-5252525")).to be_nil
  end

  it "fails with a validation error when checksum does not match" do
    records = [
      {
        type: "dataset",
        dataset_id: "IDB-6262626",
        title: "Checksum Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu"
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")
    File.write(checksum_path, "deadbeef  #{bundle_path.basename}\n")

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("bundle checksum mismatch")
    expect(Dataset.find_by(key: "IDB-6262626")).to be_nil
  end

  it "imports multiple datasets with blank identifiers by normalizing to nil" do
    key1 = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    key2 = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    records = [
      {
        type: "dataset",
        dataset_id: key1,
        title: "Blank Identifier 1",
        identifier: "",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft"
      },
      {
        type: "dataset",
        dataset_id: key2,
        title: "Blank Identifier 2",
        identifier: "",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft"
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)
    expect(summary[:created]).to eq(2)

    first = Dataset.find_by!(key: key1)
    second = Dataset.find_by!(key: key2)

    expect(first.identifier).to be_nil
    expect(second.identifier).to be_nil
  end

  it "normalizes long legacy datafile IDs and links nested items" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    nested_item_id = SecureRandom.random_number(900_000) + 100_000

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Legacy Datafile ID Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft"
      },
      {
        type: "datafile",
        dataset_id: dataset_key,
        datafile_id: "migrate1a",
        binary_name: "test_archive.zip",
        binary_size: 2048,
        storage_root: "draft",
        storage_key: "flat/test_archive.zip"
      },
      {
        type: "nested_item",
        dataset_id: dataset_key,
        datafile_id: "migrate1a",
        item_id: "ni-#{nested_item_id}",
        parent_item_id: nil,
        item_name: "test_archive.zip",
        media_type: "application/zip",
        size: 2048,
        item_path: "test_archive.zip",
        is_directory: false
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)
    expect(summary[:record_counts]).to eq(datasets: 1, datafiles: 1, nested_items: 1)

    dataset = Dataset.find_by!(key: dataset_key)
    datafile = dataset.datafiles.first

    expect(datafile.web_id).to match(/\A[a-z0-9]{5}\z/)
    expect(datafile.nested_items.pluck(:id)).to include(nested_item_id)
  end
end
