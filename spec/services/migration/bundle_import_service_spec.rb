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
      "depositor_email" => "legacy@example.edu",
      "token" => {
        "identifier" => "legacy-upload-token",
        "expires" => "2026-06-02T12:00:00Z",
        "created_at" => "2026-06-01T08:00:00Z",
        "updated_at" => "2026-06-01T09:00:00Z"
      },
      "notes" => [
        {
          "body" => "Curator migration note",
          "author" => "curator@example.edu",
          "created_at" => "2026-06-01T09:00:00Z",
          "updated_at" => "2026-06-01T10:00:00Z"
        }
      ]
    }

    File.write(bundle_path, "#{payload.to_json}\n")

    summary = described_class.new(bundle_path: bundle_path.to_s).call

    expect(summary[:created]).to eq(1)
    dataset = Dataset.find_by!(identifier: payload["identifier"])
    expect(dataset.owner_uid).to eq("legacy-owner")
    expect(dataset.depositor_name).to eq("Legacy User")
    expect(dataset.depositor_email).to eq("legacy@example.edu")
    expect(dataset.token&.identifier).to eq("legacy-upload-token")
    expect(dataset.notes.count).to eq(1)
    expect(dataset.notes.first.body).to eq("Curator migration note")
    expect(dataset.notes.first.author).to eq("curator@example.edu")
  end

  it "replaces notes in overwrite mode" do
    dataset = Dataset.create!(
      key: "IDB-7777777",
      identifier: "10.13012/B2IDB-7777777_V1",
      title: "Original",
      owner_uid: "legacy-owner",
      depositor_name: "Legacy User",
      depositor_email: "legacy@example.edu"
    )
    dataset.notes.create!(body: "Outdated note", author: "old-curator@example.edu")

    payload = {
      "title" => "Updated Bundle Dataset",
      "identifier" => "10.13012/B2IDB-7777777_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-7777777.json",
      "owner_uid" => "legacy-owner",
      "depositor_name" => "Legacy User",
      "depositor_email" => "legacy@example.edu",
      "notes" => [
        {
          "body" => "Imported replacement note",
          "author" => "new-curator@example.edu"
        }
      ]
    }

    File.write(bundle_path, "#{payload.to_json}\n")

    summary = described_class.new(bundle_path: bundle_path.to_s, overwrite: true).call

    expect(summary[:updated]).to eq(1)
    dataset.reload
    expect(dataset.notes.pluck(:body)).to eq([ "Imported replacement note" ])
    expect(dataset.notes.pluck(:author)).to eq([ "new-curator@example.edu" ])
  end

  it "updates the single owned token when re-importing a dataset bundle" do
    dataset = Dataset.create!(
      key: "IDB-8888888",
      identifier: "10.13012/B2IDB-8888888_V1",
      title: "Original",
      owner_uid: "legacy-owner",
      depositor_name: "Legacy User",
      depositor_email: "legacy@example.edu"
    )
    dataset.create_token!(identifier: "old-token", expires: Time.zone.parse("2026-06-01T12:00:00Z"))

    payload = {
      "title" => "Updated Bundle Dataset",
      "identifier" => "10.13012/B2IDB-8888888_V1",
      "url" => "https://databank.illinois.edu/datasets/IDB-8888888.json",
      "owner_uid" => "legacy-owner",
      "depositor_name" => "Legacy User",
      "depositor_email" => "legacy@example.edu",
      "token" => {
        "identifier" => "replacement-token",
        "expires" => "2026-06-05T12:00:00Z",
        "created_at" => "2026-06-05T10:00:00Z",
        "updated_at" => "2026-06-05T11:00:00Z"
      }
    }

    File.write(bundle_path, "#{payload.to_json}\n")

    summary = described_class.new(bundle_path: bundle_path.to_s, overwrite: true).call

    expect(summary[:updated]).to eq(1)
    dataset.reload
    expect(dataset.token.identifier).to eq("replacement-token")
    expect(dataset.token.expires).to eq(Time.zone.parse("2026-06-05T12:00:00Z"))
    expect(Token.where(dataset_key: dataset.key).count).to eq(1)
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
