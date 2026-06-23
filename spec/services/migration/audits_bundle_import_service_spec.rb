require "rails_helper"
require "tmpdir"

RSpec.describe Migration::AuditsBundleImportService do
  let(:tmpdir) { Dir.mktmpdir("audits-bundle-import") }
  let(:bundle_path) { File.join(tmpdir, "legacy_audits.ndjson") }
  let(:manifest_path) { File.join(tmpdir, "manifest.json") }
  let(:checksum_path) { "#{bundle_path}.sha256" }

  after do
    FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir)
  end

  it "imports audit rows and remaps associated dataset-side records" do
    dataset = Dataset.create!(
      key: "IDB-8888001",
      title: "Audited Dataset",
      owner_uid: "owner-audit-1",
      depositor_name: "Owner Audit",
      depositor_email: "owner-audit-1@example.edu"
    )
    creator = dataset.creators.create!(
      given_name: "Ada",
      family_name: "Lovelace",
      name: "Ada Lovelace",
      position: 1,
      row_position: 1
    )
    Audited::Audit.delete_all

    payloads = [
      {
        type: "Audit",
        attributes: {
          legacy_audit_id: 1,
          dataset_key: dataset.key,
          action: "update",
          version: 1,
          request_uuid: "req-dataset",
          created_at: "2026-06-18T19:40:00Z",
          audited_changes: { "title" => [ "Old", "Audited Dataset" ] },
          auditable: { type: "Dataset", legacy_id: 100, locator: { key: dataset.key } },
          associated: nil
        }
      },
      {
        type: "Audit",
        attributes: {
          legacy_audit_id: 2,
          dataset_key: dataset.key,
          action: "update",
          version: 2,
          request_uuid: "req-creator",
          created_at: "2026-06-18T19:45:00Z",
          audited_changes: { "family_name" => [ "Byron", "Lovelace" ] },
          auditable: {
            type: "Creator",
            legacy_id: 101,
            locator: {
              row_position: 1,
              given_name: "Ada",
              family_name: "Lovelace",
              name: "Ada Lovelace"
            }
          },
          associated: { type: "Dataset", legacy_id: 100, locator: { key: dataset.key } }
        }
      }
    ]

    write_bundle(payloads)

    summary = described_class.new(
      bundle_path: bundle_path,
      checksum_path: checksum_path,
      manifest_path: manifest_path
    ).call

    expect(summary[:created]).to eq(2)
    expect(summary[:failed]).to eq(0)

    creator_audit = Audited::Audit.find_by!(request_uuid: "req-creator")
    expect(creator_audit.auditable_type).to eq("Creator")
    expect(creator_audit.auditable_id).to eq(creator.id)
    expect(creator_audit.associated_type).to eq("Dataset")
    expect(creator_audit.associated_id).to eq(dataset.id)
  end

  it "uses deterministic synthetic ids for missing audited child records" do
    dataset = Dataset.create!(
      key: "IDB-8888002",
      title: "Deleted Child Audit Dataset",
      owner_uid: "owner-audit-2",
      depositor_name: "Owner Audit",
      depositor_email: "owner-audit-2@example.edu"
    )
    Audited::Audit.delete_all

    payloads = [
      {
        type: "Audit",
        attributes: {
          legacy_audit_id: 3,
          dataset_key: dataset.key,
          action: "create",
          version: 1,
          request_uuid: "req-missing-1",
          created_at: "2026-06-18T19:50:00Z",
          audited_changes: { "uri" => [ nil, "https://doi.org/10.1000/deleted" ] },
          auditable: {
            type: "RelatedMaterial",
            legacy_id: 201,
            locator: {
              uri: "https://doi.org/10.1000/deleted",
              citation: "Deleted article",
              material_type: "Article",
              title: "Deleted article"
            }
          },
          associated: { type: "Dataset", legacy_id: 200, locator: { key: dataset.key } }
        }
      },
      {
        type: "Audit",
        attributes: {
          legacy_audit_id: 4,
          dataset_key: dataset.key,
          action: "destroy",
          version: 2,
          request_uuid: "req-missing-2",
          created_at: "2026-06-18T19:55:00Z",
          audited_changes: { "uri" => [ "https://doi.org/10.1000/deleted", nil ] },
          auditable: {
            type: "RelatedMaterial",
            legacy_id: 201,
            locator: {
              uri: "https://doi.org/10.1000/deleted",
              citation: "Deleted article",
              material_type: "Article",
              title: "Deleted article"
            }
          },
          associated: { type: "Dataset", legacy_id: 200, locator: { key: dataset.key } }
        }
      }
    ]

    write_bundle(payloads)

    summary = described_class.new(
      bundle_path: bundle_path,
      checksum_path: checksum_path,
      manifest_path: manifest_path
    ).call

    expect(summary[:created]).to eq(2)
    imported = Audited::Audit.where(auditable_type: "RelatedMaterial").order(:created_at)
    expect(imported.count).to eq(2)
    expect(imported.first.auditable_id).to be < 0
    expect(imported.first.auditable_id).to eq(imported.second.auditable_id)
    expect(imported.first.associated_id).to eq(dataset.id)
  end

  def write_bundle(payloads)
    digest = Digest::SHA256.new

    File.open(bundle_path, "w") do |file|
      payloads.each do |payload|
        line = JSON.generate(payload)
        file.write(line)
        file.write("\n")
        digest.update(line)
        digest.update("\n")
      end
    end

    checksum = digest.hexdigest
    File.write(checksum_path, "#{checksum}  legacy_audits.ndjson\n")
    File.write(
      manifest_path,
      JSON.pretty_generate(
        {
          generated_at: Time.current.utc.iso8601,
          bundle_file: "legacy_audits.ndjson",
          record_count: payloads.length,
          sha256: checksum,
          counts: { "Audit" => payloads.length }
        }
      )
    )
  end
end
