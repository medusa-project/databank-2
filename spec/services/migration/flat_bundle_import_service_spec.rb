require "rails_helper"

RSpec.describe Migration::FlatBundleImportService do
  let(:bundle_path) { Rails.root.join("tmp", "spec_flat_migration_bundle.ndjson") }
  let(:checksum_path) { Rails.root.join("tmp", "spec_flat_migration_bundle.ndjson.sha256") }
  let(:checkpoint_path) { Rails.root.join("tmp", "spec_flat_migration_bundle.checkpoint.json") }

  after do
    FileUtils.rm_f(bundle_path)
    FileUtils.rm_f(checksum_path)
    FileUtils.rm_f(checkpoint_path)
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

  it "imports a full Datafile batch whose dataset is in a partial dataset batch" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Interleaved Flat Bundle Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft"
      }
    ]

    100.times do |index|
      records << {
        type: "datafile",
        dataset_id: dataset_key,
        datafile_id: "a#{index.to_s.rjust(4, '0')}",
        binary_name: "file-#{index}.txt",
        binary_size: index + 1
      }
    end

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)
    expect(summary[:record_counts]).to include(datasets: 1, datafiles: 100)
    expect(Dataset.find_by!(key: dataset_key).datafiles.count).to eq(100)
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

  it "normalizes legacy embargo labels to target values" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Legacy Embargo Label Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "metadata embargo",
        release_date: Date.current.iso8601
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)

    dataset = Dataset.find_by!(key: dataset_key)
    expect(dataset.embargo).to eq("metadata")
  end

  it "defaults blank dataset titles and continues processing the batch" do
    untitled_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    valid_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    records = [
      {
        type: "dataset",
        dataset_id: untitled_key,
        title: nil,
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      },
      {
        type: "dataset",
        dataset_id: valid_key,
        title: "Valid Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)
    expect(summary[:created]).to eq(2)
    expect(Dataset.find_by(key: untitled_key)&.title).to eq("Untitled Dataset")
    expect(Dataset.find_by(key: valid_key)).to be_present
  end

  it "imports funder code from flat dataset records" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Funder Code Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none",
        funders: [
          {
            name: "National Science Foundation",
            code: "NSF",
            grant: "NSF-123"
          }
        ]
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)

    dataset = Dataset.find_by!(key: dataset_key)
    expect(dataset.funders.count).to eq(1)
    expect(dataset.funders.first.code).to eq("NSF")
  end

  it "keeps multiple same-name funders when grants differ" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Duplicate Name Funder Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none",
        funders: [
          {
            name: "National Science Foundation",
            code: "NSF",
            grant: "NSF-111"
          },
          {
            name: "National Science Foundation",
            code: "NSF",
            grant: "NSF-222"
          }
        ]
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)

    dataset = Dataset.find_by!(key: dataset_key)
    expect(dataset.funders.count).to eq(2)
    expect(dataset.funders.order(:grant).pluck(:name, :grant)).to eq(
      [
        [ "National Science Foundation", "NSF-111" ],
        [ "National Science Foundation", "NSF-222" ]
      ]
    )
  end

  it "remaps colliding valid web_ids that belong to another dataset" do
    existing_dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    import_dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    existing_dataset = Dataset.create!(
      key: existing_dataset_key,
      title: "Existing Dataset",
      owner_uid: "legacy-owner",
      depositor_name: "Legacy User",
      depositor_email: "legacy@example.edu",
      publication_state: :draft,
      embargo: "none"
    )
    existing_dataset.datafiles.create!(web_id: "ab123", binary_name: "existing.csv")

    records = [
      {
        type: "dataset",
        dataset_id: import_dataset_key,
        title: "Incoming Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      },
      {
        type: "datafile",
        dataset_id: import_dataset_key,
        datafile_id: "ab123",
        binary_name: "incoming.csv",
        binary_size: 111,
        storage_root: "draft",
        storage_key: "flat/incoming.csv"
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)

    imported_dataset = Dataset.find_by!(key: import_dataset_key)
    imported_datafile = imported_dataset.datafiles.first

    expect(imported_datafile.web_id).to match(/\A[a-z0-9]{5}\z/)
    expect(imported_datafile.web_id).not_to eq("ab123")
  end

  it "normalizes legacy datafile archive/listing peek_type to listing" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Legacy Peek Type Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      },
      {
        type: "datafile",
        dataset_id: dataset_key,
        datafile_id: "ab123",
        binary_name: "archive.zip",
        binary_size: 100,
        storage_root: "draft",
        storage_key: "flat/archive.zip",
        peek_type: Datafile::PeekType::LISTING,
        peek_text: "archive listing"
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)

    dataset = Dataset.find_by!(key: dataset_key)
    datafile = dataset.datafiles.find_by!(binary_name: "archive.zip")

    expect(datafile.peek_type).to eq(Datafile::PeekType::LISTING)
    expect(datafile.peek_content).to eq("archive listing")
  end

  it "imports nested items even when nested records appear before datafile records" do
    dataset_key = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    nested_count = 120

    nested_records = (1..nested_count).map do |idx|
      {
        type: "nested_item",
        dataset_id: dataset_key,
        datafile_id: "ab123",
        item_id: "ni-#{idx}",
        parent_item_id: nil,
        item_name: "file_#{idx}.txt",
        media_type: "text/plain",
        size: idx,
        item_path: "folder/file_#{idx}.txt",
        is_directory: false
      }
    end

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key,
        title: "Interleaved Nested Dataset",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      }
    ] + nested_records + [
      {
        type: "datafile",
        dataset_id: dataset_key,
        datafile_id: "ab123",
        binary_name: "archive.zip",
        binary_size: 2048,
        storage_root: "draft",
        storage_key: "flat/archive.zip",
        peek_type: Datafile::PeekType::LISTING,
        peek_text: "archive listing"
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(0)
    expect(summary.dig(:record_counts, :nested_items)).to eq(nested_count)

    dataset = Dataset.find_by!(key: dataset_key)
    datafile = dataset.datafiles.find_by!(web_id: "ab123")
    expect(datafile.nested_items.count).to eq(nested_count)
  end

  it "uses env-configurable batch size and pause between batches" do
    dataset_keys = Array.new(3) { "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}" }

    records = dataset_keys.map do |key|
      {
        type: "dataset",
        dataset_id: key,
        title: "Batch Config Dataset #{key}",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      }
    end

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    begin
      ENV["FLAT_BUNDLE_IMPORT_BATCH_SIZE"] = "2"
      ENV["FLAT_BUNDLE_IMPORT_BATCH_PAUSE_SECONDS"] = "0.01"

      service = described_class.new(bundle_path: bundle_path.to_s, dry_run: true)
      expect(service).to receive(:sleep).with(0.01).at_least(:once)

      summary = service.call

      expect(summary[:failed]).to eq(0)
      expect(summary.dig(:record_counts, :datasets)).to eq(3)
    ensure
      ENV.delete("FLAT_BUNDLE_IMPORT_BATCH_SIZE")
      ENV.delete("FLAT_BUNDLE_IMPORT_BATCH_PAUSE_SECONDS")
    end
  end

  it "supports windowed processing with resume line and max records" do
    dataset_key_1 = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"
    dataset_key_2 = "IDB-#{SecureRandom.random_number(9_000_000) + 1_000_000}"

    records = [
      {
        type: "dataset",
        dataset_id: dataset_key_1,
        title: "Window Dataset 1",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      },
      {
        type: "dataset",
        dataset_id: dataset_key_2,
        title: "Window Dataset 2",
        owner_uid: "legacy-owner",
        depositor_name: "Legacy User",
        depositor_email: "legacy@example.edu",
        publication_state: "draft",
        embargo: "none"
      }
    ]

    File.write(bundle_path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")

    begin
      ENV["FLAT_BUNDLE_IMPORT_MAX_RECORDS"] = "1"
      ENV["FLAT_BUNDLE_IMPORT_RESUME_FROM_LINE"] = "1"
      ENV["FLAT_BUNDLE_IMPORT_CHECKPOINT_FILE"] = checkpoint_path.to_s

      first_summary = described_class.new(bundle_path: bundle_path.to_s).call
      expect(first_summary[:processed_count]).to eq(1)
      expect(first_summary[:stopped_early]).to eq(true)
      expect(first_summary[:next_resume_from_line]).to eq(2)

      checkpoint = JSON.parse(File.read(checkpoint_path))
      expect(checkpoint["next_resume_from_line"]).to eq(2)

      ENV["FLAT_BUNDLE_IMPORT_RESUME_FROM_LINE"] = checkpoint["next_resume_from_line"].to_s

      second_summary = described_class.new(bundle_path: bundle_path.to_s).call
      expect(second_summary[:processed_count]).to eq(1)
      expect(second_summary[:stopped_early]).to eq(false)
      expect(Dataset.find_by(key: dataset_key_1)).to be_present
      expect(Dataset.find_by(key: dataset_key_2)).to be_present
    ensure
      ENV.delete("FLAT_BUNDLE_IMPORT_MAX_RECORDS")
      ENV.delete("FLAT_BUNDLE_IMPORT_RESUME_FROM_LINE")
      ENV.delete("FLAT_BUNDLE_IMPORT_CHECKPOINT_FILE")
    end
  end
end
