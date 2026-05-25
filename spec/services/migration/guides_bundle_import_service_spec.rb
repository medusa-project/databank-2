require "rails_helper"
require "digest"

RSpec.describe Migration::GuidesBundleImportService do
  let(:tmp_root) { Rails.root.join("tmp", "spec_guides_bundle") }
  let(:bundle_path) { tmp_root.join("legacy_guides.ndjson") }
  let(:checksum_path) { tmp_root.join("legacy_guides.ndjson.sha256") }
  let(:manifest_path) { tmp_root.join("manifest.json") }

  before do
    ActionText::RichText.where(record_type: [ "Guide::Section", "Guide::Item", "Guide::Subitem" ], name: "body").delete_all
    Guide::Subitem.delete_all
    Guide::Item.delete_all
    Guide::Section.delete_all

    FileUtils.rm_rf(tmp_root)
    FileUtils.mkdir_p(tmp_root)
  end

  after do
    FileUtils.rm_rf(tmp_root)
  end

  it "imports guides hierarchy and rich text bodies" do
    write_bundle_and_artifacts(valid_payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:created]).to eq(3)
    expect(summary[:failed]).to eq(0)

    section = Guide::Section.find_by!(anchor: "submission")
    item = Guide::Item.find_by!(anchor: "login")
    subitem = Guide::Subitem.find_by!(anchor: "upload_tools")

    expect(item.section_id).to eq(section.id)
    expect(subitem.item_id).to eq(item.id)
    expect(section.body.to_s).to include("Section body")
    expect(item.body.to_s).to include("Item body")
    expect(subitem.body.to_s).to include("Subitem body")
  end

  it "supports dry run without writing records" do
    write_bundle_and_artifacts(valid_payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s,
      dry_run: true
    ).call

    expect(summary[:would_create]).to eq(3)
    expect(summary[:failed]).to eq(0)
    expect(Guide::Section.count).to eq(0)
    expect(Guide::Item.count).to eq(0)
    expect(Guide::Subitem.count).to eq(0)
  end

  it "fails when checksum does not match" do
    write_bundle(valid_payloads)
    File.write(checksum_path, "deadbeef  legacy_guides.ndjson\n")

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("bundle checksum mismatch")
  end

  it "fails when manifest record count does not match" do
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

  it "fails when item references unknown section" do
    payloads = valid_payloads
    payloads[1]["attributes"]["section_id"] = 999
    write_bundle_and_artifacts(payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("item references unknown section_id=999")
  end

  it "fails when format_version is unsupported" do
    write_bundle(valid_payloads)
    write_checksum
    write_manifest(valid_payloads, format_version: 2)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:failed]).to eq(1)
    expect(summary[:validation_error]).to eq("unsupported guides bundle format_version")
  end

  it "sanitizes imported html and hardens external links" do
    payloads = valid_payloads
    payloads[0]["attributes"]["body"] = <<~HTML
      <p>Safe</p>
      <script>alert('xss')</script>
      <a href="javascript:alert(1)" target="_blank">bad link</a>
      <a href="https://example.org" target="_blank">good link</a>
      <img src="data:text/html;base64,abc" alt="bad image" />
      <img src="/dataset_title.png" />
    HTML
    write_bundle_and_artifacts(payloads)

    summary = described_class.new(
      bundle_path: bundle_path.to_s,
      checksum_path: checksum_path.to_s,
      manifest_path: manifest_path.to_s
    ).call

    expect(summary[:failed]).to eq(0)
    section_html = Guide::Section.find_by!(anchor: "submission").body.to_s
    expect(section_html).to include("Safe")
    expect(section_html).not_to include("script")
    expect(section_html).not_to include("alert('xss')")
    expect(section_html).not_to include("javascript:")
    expect(section_html).to include("href=\"https://example.org\"")
    expect(section_html).not_to include("data:text/html")
    expect(section_html).to include("alt=\"Dataset Title\"")
  end

  private

  def valid_payloads
    [
      {
        "type" => "Guide::Section",
        "attributes" => {
          "id" => 1,
          "anchor" => "submission",
          "label" => "Submission",
          "ordinal" => 1,
          "public" => true,
          "heading" => "Submission",
          "body" => "<p>Section body</p>",
          "created_at" => "2026-01-01 00:00:00 UTC",
          "updated_at" => "2026-01-01 00:00:00 UTC"
        }
      },
      {
        "type" => "Guide::Item",
        "attributes" => {
          "id" => 10,
          "section_id" => 1,
          "anchor" => "login",
          "label" => "Log In",
          "ordinal" => 1,
          "public" => true,
          "heading" => "Log in",
          "body" => "<p>Item body</p>",
          "created_at" => "2026-01-01 00:00:00 UTC",
          "updated_at" => "2026-01-01 00:00:00 UTC"
        }
      },
      {
        "type" => "Guide::Subitem",
        "attributes" => {
          "id" => 100,
          "item_id" => 10,
          "anchor" => "upload_tools",
          "label" => "Upload Tools",
          "ordinal" => 1,
          "public" => true,
          "heading" => "Upload Using Tools",
          "body" => "<p>Subitem body</p>",
          "created_at" => "2026-01-01 00:00:00 UTC",
          "updated_at" => "2026-01-01 00:00:00 UTC"
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
    File.write(checksum_path, "#{digest}  legacy_guides.ndjson\n")
  end

  def write_manifest(payloads, record_count: payloads.length, format_version: 1)
    digest = Digest::SHA256.file(bundle_path).hexdigest
    counts = payloads.each_with_object(Hash.new(0)) { |payload, acc| acc[payload["type"]] += 1 }
    manifest = {
      "generated_at" => Time.current.utc.iso8601,
      "bundle_file" => "legacy_guides.ndjson",
      "record_count" => record_count,
      "counts" => {
        "Guide::Section" => counts["Guide::Section"],
        "Guide::Item" => counts["Guide::Item"],
        "Guide::Subitem" => counts["Guide::Subitem"]
      },
      "sha256" => digest,
      "format_version" => format_version
    }
    File.write(manifest_path, JSON.pretty_generate(manifest))
  end
end
