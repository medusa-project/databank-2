require "rails_helper"

RSpec.describe Dataset::Globusable, type: :model do
  let(:dataset) do
    Dataset.create!(
      title: "Globusable Dataset",
      description: "Dataset for globusable behavior",
      owner_uid: "owner-globusable",
      depositor_name: "Owner Globusable",
      depositor_email: "owner-globusable@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE
    )
  end

  describe "#globus_downloadable?" do
    it "is false when the dataset is not published" do
      dataset.update!(publication_state: :draft, all_globus: true)

      expect(dataset.globus_downloadable?).to be false
    end

    it "is false when all_globus has not been set" do
      expect(dataset.globus_downloadable?).to be false
    end

    it "is true when the dataset is published and all_globus is true" do
      dataset.update!(all_globus: true)

      expect(dataset.globus_downloadable?).to be true
    end

    it "rechecks availability after state changes on the same instance" do
      dataset.update!(all_globus: true)
      expect(dataset.globus_downloadable?).to be true

      dataset.update!(hold_state: Dataset::HOLD_PERM_FILE)
      expect(dataset.globus_downloadable?).to be false
    end

    it "does not offer public Globus access during file or metadata embargoes" do
      [ Dataset::EMBARGO_FILE, Dataset::EMBARGO_METADATA ].each do |embargo|
        dataset.update!(all_globus: true, embargo: embargo, release_date: Date.tomorrow)
        expect(dataset.globus_downloadable?).to be false

        dataset.update!(release_date: Date.yesterday)
        expect(dataset.globus_downloadable?).to be true
      end
    end

    it "does not offer public Globus access for suppressed or test datasets" do
      Dataset::HOLD_FILE_BLOCKING_STATES.each do |hold|
        dataset.update!(all_globus: true, hold_state: hold)
        expect(dataset.globus_downloadable?).to be false
      end
      dataset.update!(hold_state: Dataset::HOLD_NONE, is_test: true)
      expect(dataset.globus_downloadable?).to be false
    end
  end

  describe "File Manager URLs" do
    before { allow(IdbConfig).to receive(:fetch).and_call_original }

    it "appends the dataset directory to the decoded origin path" do
      allow(IdbConfig).to receive(:fetch).with(:globus, :download_url_base)
        .and_return("https://app.globus.org/file-manager?origin_id=download&origin_path=%2Fpublic%20files%2F")

      uri = URI(dataset.globus_download_dir)
      expect(uri.host).to eq("app.globus.org")
      expect(URI.decode_www_form(uri.query).to_h).to eq(
        "origin_id" => "download", "origin_path" => "/public files/#{dataset.key}"
      )
    end

    it "provides the ingest File Manager URL" do
      dataset
      allow(IdbConfig).to receive(:fetch).with(:globus, :ingest_url_base)
        .and_return("https://app.globus.org/file-manager?origin_id=ingest&origin_path=%2Fingest")
      expect(URI.decode_www_form(URI(dataset.globus_ingest_dir).query).to_h["origin_path"])
        .to eq("/ingest/#{dataset.key}")
    end

    it "reports missing and invalid configuration explicitly" do
      [ "", "javascript:alert(1)", "https://app.globus.org/file-manager", "https://[" ].each do |base|
        allow(IdbConfig).to receive(:fetch).with(:globus, :download_url_base).and_return(base)
        expect { dataset.globus_download_dir }.to raise_error(Dataset::Globusable::Error)
      end
    end
  end

  describe "ingest storage operations" do
    let(:root) { instance_double("MedusaStorage::Root", root_type: :s3) }

    before do
      dataset
      allow(StorageManager.instance).to receive(:globus_ingest_root).and_return(root)
    end

    it "creates the directory marker in the ingest root, not the draft root" do
      allow(root).to receive(:exist?).with("#{dataset.key}/").and_return(false, true)
      expect(root).to receive(:write_string_to).with("#{dataset.key}/", "")
      expect(dataset.ensure_globus_ingest_dir).to be true
    end

    it "does not rewrite an existing directory" do
      allow(root).to receive(:exist?).with("#{dataset.key}/").and_return(true)
      expect(root).not_to receive(:write_string_to)
      expect(dataset.ensure_globus_ingest_dir).to be true
    end

    it "copies a source file with an optional filename override" do
      source = instance_double("MedusaStorage::Root", exist?: true)
      allow(StorageManager.instance.root_set).to receive(:at).with("draft").and_return(source)
      allow(root).to receive(:exist?).with("#{dataset.key}/").and_return(true)
      expect(root).to receive(:copy_content_to).with("#{dataset.key}/renamed.csv", source, "source/analysis.csv")

      dataset.copy_to_globus_ingest_dir(source_root_name: "draft", source_key: "source/analysis.csv", target_name_override: "renamed.csv")
    end

    it "rejects missing source files and path traversal overrides" do
      source = instance_double("MedusaStorage::Root")
      allow(StorageManager.instance.root_set).to receive(:at).with("draft").and_return(source)
      allow(source).to receive(:exist?).and_return(false)
      expect { dataset.copy_to_globus_ingest_dir(source_root_name: "draft", source_key: "missing") }
        .to raise_error(Dataset::Globusable::Error, "Source file not found")
      allow(source).to receive(:exist?).and_return(true)
      expect { dataset.copy_to_globus_ingest_dir(source_root_name: "draft", source_key: "source", target_name_override: "../escape") }
        .to raise_error(Dataset::Globusable::Error, "Invalid Globus ingest filename")
    end

    it "deletes an ingest file with exactly one dataset prefix" do
      target_key = "#{dataset.key}/notes.csv"
      allow(root).to receive(:exist?).with(target_key).and_return(true)
      expect(root).to receive(:delete_content).with(target_key).twice

      dataset.delete_from_globus_ingest_dir(storage_key: "notes.csv")
      dataset.delete_from_globus_ingest_dir(storage_key: target_key)
    end

    it "rejects deletion outside the dataset directory" do
      expect(root).not_to receive(:delete_content)
      expect { dataset.delete_from_globus_ingest_dir(storage_key: "../other/notes.csv") }
        .to raise_error(Dataset::Globusable::Error)
    end

    it "removes dataset ingest files and the directory marker" do
      allow(root).to receive(:exist?).with("#{dataset.key}/").and_return(true)
      allow(root).to receive(:file_keys).with(dataset.key).and_return([ "#{dataset.key}/notes.csv" ])
      expect(root).to receive(:delete_content).with("#{dataset.key}/notes.csv")
      expect(root).to receive(:delete_content).with("#{dataset.key}/")
      expect(dataset.remove_globus_ingest_dir).to be true
    end

    it "does not delete ingest files referenced by another dataset version" do
      other = Dataset.create!(title: "Other", owner_uid: "other", depositor_name: "Other", depositor_email: "other@example.edu")
      other.datafiles.create!(binary_name: "notes.csv", storage_root: "draft", storage_key: "#{dataset.key}/notes.csv")
      allow(root).to receive(:exist?).with("#{dataset.key}/").and_return(true)
      allow(root).to receive(:file_keys).with(dataset.key).and_return([ "#{dataset.key}/notes.csv" ])
      expect(root).not_to receive(:delete_content)

      expect { dataset.remove_globus_ingest_dir }.to raise_error(Dataset::Globusable::Error, /still referenced/)
    end

    it "reports a missing ingest directory instead of claiming an import succeeded" do
      allow(root).to receive(:exist?).with("#{dataset.key}/").and_return(false)
      allow(root).to receive(:file_keys).with(dataset.key).and_return([])
      expect { dataset.import_from_globus }.to raise_error(Dataset::Globusable::Error, /not found/)
    end

    it "provisions and removes filesystem-backed ingest directories" do
      Dir.mktmpdir("globus-directory-spec-") do |directory|
        filesystem_root = MedusaStorage::Root::Filesystem.new(name: "globus_ingest", path: directory)
        allow(StorageManager.instance).to receive(:globus_ingest_root).and_return(filesystem_root)

        expect(dataset.ensure_globus_ingest_dir).to be true
        filesystem_root.write_string_to("#{dataset.key}/notes.csv", "notes")
        expect(dataset.remove_globus_ingest_dir).to be true
        expect(filesystem_root.exist?("#{dataset.key}/")).to be false
      end
    end
  end

  describe "storage lifecycle callbacks" do
    it "does not provision storage when the ingest File Manager is not configured" do
      allow(IdbConfig).to receive(:fetch).and_call_original
      allow(IdbConfig).to receive(:fetch).with(:globus, :ingest_url_base).and_return("")
      expect(StorageManager.instance).not_to receive(:globus_ingest_root)
      dataset
    end

    it "creates ingest directories only when the ingest File Manager is configured" do
      allow(IdbConfig).to receive(:fetch).and_call_original
      allow(IdbConfig).to receive(:fetch).with(:globus, :ingest_url_base).and_return("https://app.globus.org/file-manager")
      root = instance_double("MedusaStorage::Root", root_type: :s3)
      allow(StorageManager.instance).to receive(:globus_ingest_root).and_return(root)
      allow(root).to receive(:exist?).and_return(false, true)
      expect(root).to receive(:write_string_to).with(a_string_matching(%r{\AIDB-\d+/\z}), "")
      dataset
    end

    it "cleans Globus storage before deleting the dataset" do
      dataset.update!(all_globus: true)
      allow(dataset).to receive(:globus_ingest_configured?).and_return(true)
      expect(dataset).to receive(:remove_globus_ingest_dir).ordered
      expect(dataset).to receive(:remove_from_globus_download).ordered.and_return(true)
      dataset.destroy!
      expect(dataset).to be_destroyed
    end

    it "does not delete the dataset when public storage cleanup fails" do
      dataset.update!(all_globus: true)
      allow(dataset).to receive(:remove_from_globus_download).and_return(false)
      expect { dataset.destroy! }.to raise_error(Dataset::Globusable::Error, /Unable to remove/)
      expect(dataset.reload).to be_persisted
    end
  end

  describe "#too_big?" do
    it "uses the configured GiB threshold with a strict greater-than comparison" do
      allow(IdbConfig).to receive(:fetch).and_call_original
      allow(IdbConfig).to receive(:fetch).with(:globus, :only_gb, default: 2).and_return(2)
      file = dataset.datafiles.create!(binary_name: "large.zip", binary_size: 2 * (2**30))
      expect(dataset.too_big?).to be false

      file.update!(binary_size: file.binary_size + 1)
      expect(dataset.too_big?).to be true
    end

    it "reports invalid thresholds rather than silently treating them as zero" do
      dataset
      allow(IdbConfig).to receive(:fetch).and_call_original
      [ "invalid", -1, 0, Float::INFINITY ].each do |limit|
        allow(IdbConfig).to receive(:fetch).with(:globus, :only_gb, default: 2).and_return(limit)
        expect { dataset.too_big? }.to raise_error(Dataset::Globusable::Error, /positive finite/)
      end
    end
  end

  describe "#fileset_preserved?" do
    it "is false when the dataset is not published" do
      dataset.update!(publication_state: :draft, all_medusa: true)

      expect(dataset.fileset_preserved?).to be false
    end

    it "is false when all_medusa has not been set" do
      expect(dataset.fileset_preserved?).to be false
    end

    it "is true when the dataset is published and all_medusa is true" do
      dataset.update!(all_medusa: true)

      expect(dataset.fileset_preserved?).to be true
    end
  end
end
