require "rails_helper"
require "digest"

RSpec.describe Migration::FeaturedResearchersBundleImportService do
  let(:tmp_root) { Rails.root.join("tmp", "spec_featured_researchers_bundle") }
  let(:bundle_path) { tmp_root.join("legacy_featured_researchers.ndjson") }
  let(:checksum_path) { tmp_root.join("legacy_featured_researchers.ndjson.sha256") }
  let(:manifest_path) { tmp_root.join("manifest.json") }

  before do
    FeaturedResearcher.delete_all
    FileUtils.rm_rf(tmp_root)
    FileUtils.mkdir_p(tmp_root)
  end

  after do
    FileUtils.rm_rf(tmp_root)
  end

  it "imports featured researchers from a valid bundle" do
    write_bundle_and_artifacts(valid_payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:created]).to eq(2)
    expect(summary[:failed]).to eq(0)
    expect(FeaturedResearcher.count).to eq(2)

    imported = FeaturedResearcher.find_by!(id: 1)
    expect(imported.name).to eq("Researcher One")
    expect(imported.is_active).to be(true)
    expect(imported.dataset_url).to eq("https://example.org/dataset/1")
  end

  it "supports dry run status reporting without writing records" do
    existing = FeaturedResearcher.create!(
      id: 1,
      name: "Existing",
      is_active: false,
      created_at: Time.current,
      updated_at: Time.current
    )

    write_bundle_and_artifacts(valid_payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s,
      dry_run: true,
      replace_all: false,
      overwrite: true
    ).call

    expect(summary[:would_update]).to eq(1)
    expect(summary[:would_create]).to eq(1)
    expect(summary[:failed]).to eq(0)
    expect(FeaturedResearcher.find(existing.id).name).to eq("Existing")
    expect(FeaturedResearcher.count).to eq(1)
  end

  it "updates existing records when overwrite is true and replace_all is false" do
    FeaturedResearcher.create!(
      id: 1,
      name: "Old Name",
      question: "Old Question",
      is_active: false,
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    write_bundle_and_artifacts(valid_payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s,
      replace_all: false,
      overwrite: true
    ).call

    expect(summary[:updated]).to eq(1)
    expect(summary[:created]).to eq(1)
    expect(summary[:failed]).to eq(0)

    updated = FeaturedResearcher.find(1)
    expect(updated.name).to eq("Researcher One")
    expect(updated.question).to eq("What motivated your project?")
    expect(updated.is_active).to be(true)
  end

  it "reports skipped_existing in dry run when overwrite is false and record exists" do
    FeaturedResearcher.create!(
      id: 1,
      name: "Existing",
      is_active: false,
      created_at: Time.current,
      updated_at: Time.current
    )

    write_bundle_and_artifacts(valid_payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s,
      dry_run: true,
      replace_all: false,
      overwrite: false
    ).call

    expect(summary[:skipped_existing]).to eq(1)
    expect(summary[:would_create]).to eq(1)
    expect(summary[:failed]).to eq(0)
  end

  it "fails when checksum does not match" do
    write_bundle(valid_payloads)
    File.write(checksum_path, "deadbeef  legacy_featured_researchers.ndjson\n")

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("bundle checksum mismatch")
  end

  it "fails when duplicate ids are present in bundle" do
    payloads = valid_payloads
    payloads << payloads.first.deep_dup
    write_bundle_and_artifacts(payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("duplicate spotlight ids in bundle: 1")
  end

  it "fails when manifest count does not match payload count" do
    write_bundle(valid_payloads)
    write_checksum
    write_manifest(valid_payloads, record_count: 99)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("bundle record count mismatch")
  end

  it "fails when manifest format_version is unsupported" do
    write_bundle(valid_payloads)
    write_checksum
    write_manifest(valid_payloads, format_version: 2)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("unsupported spotlights bundle format_version")
  end

  it "fails when timestamp fields are invalid" do
    payloads = valid_payloads
    payloads.first["attributes"]["created_at"] = "not-a-time"
    write_bundle_and_artifacts(payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("invalid created_at for spotlight id=1")
  end

  it "replaces existing spotlight rows when replace_all is true" do
    FeaturedResearcher.create!(
      id: 99,
      name: "Legacy spotlight",
      is_active: false,
      created_at: Time.current,
      updated_at: Time.current
    )

    write_bundle_and_artifacts(valid_payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s,
      replace_all: true
    ).call

    expect(summary[:created]).to eq(2)
    expect(summary[:failed]).to eq(0)
    expect(FeaturedResearcher.exists?(id: 99)).to be(false)
    expect(FeaturedResearcher.order(:id).pluck(:id)).to eq([ 1, 2 ])
  end

  private

  def valid_payloads
    [
      {
        "type" => "FeaturedResearcher",
        "attributes" => {
          "id" => 1,
          "name" => "Researcher One",
          "question" => "What motivated your project?",
          "testimonial" => "This repository made sharing easy.",
          "bio" => "Researcher profile text.",
          "photo_url" => "https://example.org/photos/1.jpg",
          "dataset_url" => "https://example.org/dataset/1",
          "article_url" => "https://example.org/article/1",
          "is_active" => true,
          "created_at" => "2026-01-01 00:00:00 UTC",
          "updated_at" => "2026-01-02 00:00:00 UTC"
        }
      },
      {
        "type" => "FeaturedResearcher",
        "attributes" => {
          "id" => 2,
          "name" => "Researcher Two",
          "question" => "How did curation help?",
          "testimonial" => "Metadata review improved reuse.",
          "bio" => "Another profile.",
          "photo_url" => "https://example.org/photos/2.jpg",
          "dataset_url" => "https://example.org/dataset/2",
          "article_url" => "https://example.org/article/2",
          "is_active" => false,
          "created_at" => "2026-01-01 00:00:00 UTC",
          "updated_at" => "2026-01-02 00:00:00 UTC"
        }
      }
    ]
  end

  def write_bundle_and_artifacts(payloads)
    write_bundle(payloads)
    write_checksum
    write_manifest(payloads)
  end

  def write_bundle(payloads)
    File.write(bundle_path, payloads.map(&:to_json).join("\n") + "\n")
  end

  def write_checksum
    digest = Digest::SHA256.file(bundle_path).hexdigest
    File.write(checksum_path, "#{digest}  legacy_featured_researchers.ndjson\n")
  end

  def write_manifest(payloads, record_count: payloads.length, format_version: 1)
    digest = Digest::SHA256.file(bundle_path).hexdigest
    manifest = {
      "generated_at" => Time.current.utc.iso8601,
      "bundle_file" => "legacy_featured_researchers.ndjson",
      "record_count" => record_count,
      "counts" => {
        "FeaturedResearcher" => payloads.length
      },
      "sha256" => digest,
      "format_version" => format_version
    }

    File.write(manifest_path, JSON.pretty_generate(manifest))
  end
end
