require "rails_helper"
require "digest"

RSpec.describe Migration::BundleImportService do
  let(:bundle_path) { Rails.root.join("tmp", "spec_migration_bundle.ndjson") }
  let(:checksum_path) { Rails.root.join("tmp", "spec_migration_bundle.ndjson.sha256") }
  let(:manifest_path) { Rails.root.join("tmp", "spec_migration_bundle_manifest.json") }

  after do
    FileUtils.rm_f(bundle_path)
    FileUtils.rm_f(checksum_path)
    FileUtils.rm_f(manifest_path)
  end

  it "fails records missing sensitive depositor fields" do
    payload = {
      "title" => "Bundle Dataset",
      "identifier" => "10.13012/B2IDB-1111111_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-1111111.json"
    }

    File.write(bundle_path, "#{payload.to_json}\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:failed]).to eq(1)
    expect(Dataset.find_by(identifier: payload["identifier"])).to be_nil
  end

  it "imports records with sensitive fields" do
    payload = {
      "title" => "Bundle Dataset",
      "identifier" => "10.13012/B2IDB-2222222_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-2222222.json",
      "owner_uid" => "legacy-owner",
      "depositor_name" => "Legacy User",
      "depositor_email" => "legacy@example.edu"
    }

    File.write(bundle_path, "#{payload.to_json}\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:created]).to eq(1)
    dataset = Dataset.find_by!(identifier: payload["identifier"])
    expect(dataset.owner_uid).to eq("legacy-owner")
    expect(dataset.depositor_name).to eq("Legacy User")
    expect(dataset.depositor_email).to eq("legacy@example.edu")
  end

  it "fails when checksum does not match" do
    payload = {
      "title" => "Bundle Dataset",
      "identifier" => "10.13012/B2IDB-3333333_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-3333333.json",
      "owner_uid" => "legacy-owner",
      "depositor_name" => "Legacy User",
      "depositor_email" => "legacy@example.edu"
    }

    File.write(bundle_path, "#{payload.to_json}\n")
    File.write(checksum_path, "deadbeef  #{bundle_path.basename}\n")

    summary = described_class.new(bundle_path: bundle_path.to_s, checksum_path: checksum_path.to_s).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("bundle checksum mismatch")
    expect(Dataset.find_by(identifier: payload["identifier"])).to be_nil
  end

  it "validates manifest checksum and record count" do
    payload = {
      "title" => "Bundle Dataset",
      "identifier" => "10.13012/B2IDB-4444444_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-4444444.json",
      "owner_uid" => "legacy-owner",
      "depositor_name" => "Legacy User",
      "depositor_email" => "legacy@example.edu"
    }

    line = "#{payload.to_json}\n"
    File.write(bundle_path, line)
    sha256 = Digest::SHA256.file(bundle_path).hexdigest
    File.write(
      manifest_path,
      JSON.pretty_generate({ "bundle_file" => bundle_path.basename.to_s, "record_count" => 1, "sha256" => sha256 })
    )

    summary = described_class.new(bundle_path: bundle_path.to_s, manifest_path: manifest_path.to_s).call

    expect(summary[:created]).to eq(1)
    expect(summary[:failed]).to eq(0)
    expect(Dataset.find_by(identifier: payload["identifier"])).not_to be_nil
  end

  it "returns validation error when bundle path is missing" do
    summary = described_class.new(bundle_path: Rails.root.join("tmp", "missing_bundle.ndjson").to_s).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to include("bundle not found")
  end

  it "returns validation error when checksum path is missing" do
    payload = {
      "title" => "Bundle Dataset",
      "identifier" => "10.13012/B2IDB-5555555_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-5555555.json",
      "owner_uid" => "legacy-owner",
      "depositor_name" => "Legacy User",
      "depositor_email" => "legacy@example.edu"
    }

    File.write(bundle_path, "#{payload.to_json}\n")

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: Rails.root.join("tmp", "missing.sha256").to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to include("checksum file not found")
  end

  it "returns validation error when manifest path is missing" do
    payload = {
      "title" => "Bundle Dataset",
      "identifier" => "10.13012/B2IDB-6666666_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-6666666.json",
      "owner_uid" => "legacy-owner",
      "depositor_name" => "Legacy User",
      "depositor_email" => "legacy@example.edu"
    }

    File.write(bundle_path, "#{payload.to_json}\n")

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      manifest_path: Rails.root.join("tmp", "missing_manifest.json").to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to include("manifest file not found")
  end
end
