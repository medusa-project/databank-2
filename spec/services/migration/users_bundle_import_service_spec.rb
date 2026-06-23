require "rails_helper"
require "tmpdir"

RSpec.describe Migration::UsersBundleImportService do
  let(:tmpdir) { Dir.mktmpdir("users-bundle-import") }
  let(:bundle_path) { File.join(tmpdir, "legacy_users.ndjson") }
  let(:manifest_path) { File.join(tmpdir, "manifest.json") }
  let(:checksum_path) { "#{bundle_path}.sha256" }

  after do
    FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir)
  end

  it "creates users with supported mapped roles" do
    payloads = [
      {
        type: "User",
        attributes: {
          provider: "shibboleth",
          uid: "curator1@illinois.edu",
          email: "Curator1@Illinois.edu",
          username: "curator1",
          name: "Curator One",
          role: "admin",
          mapped_role: "curator"
        }
      }
    ]

    write_bundle(payloads)

    summary = described_class.new(
      bundle_path: bundle_path,
      checksum_path: checksum_path,
      manifest_path: manifest_path
    ).call

    expect(summary[:created]).to eq(1)
    user = User.find_by!(provider: "shibboleth", uid: "curator1@illinois.edu")
    expect(user.email).to eq("curator1@illinois.edu")
    expect(user.role).to eq("curator")
  end

  it "skips deprecated reviewer roles with logging" do
    payloads = [
      {
        type: "User",
        attributes: {
          provider: "developer",
          uid: "reviewer@example.edu",
          email: "reviewer@example.edu",
          username: "reviewer",
          name: "Reviewer Example",
          role: "network_reviewer"
        }
      }
    ]

    write_bundle(payloads)

    summary = described_class.new(
      bundle_path: bundle_path,
      checksum_path: checksum_path,
      manifest_path: manifest_path
    ).call

    expect(summary[:created]).to eq(0)
    expect(summary[:skipped_unsupported_role]).to eq(1)
    expect(User.find_by(uid: "reviewer@example.edu")).to be_nil
  end

  it "reconciles existing users by email when provider uid changed" do
    existing = User.create!(
      provider: "developer",
      uid: "old@example.edu",
      email: "person@example.edu",
      username: "person",
      name: "Person Example",
      role: "depositor"
    )

    payloads = [
      {
        type: "User",
        attributes: {
          provider: "shibboleth",
          uid: "person@example.edu",
          email: "person@example.edu",
          username: "person",
          name: "Person Example",
          role: "depositor",
          mapped_role: "depositor"
        }
      }
    ]

    write_bundle(payloads)

    summary = described_class.new(
      bundle_path: bundle_path,
      checksum_path: checksum_path,
      manifest_path: manifest_path
    ).call

    expect(summary[:updated]).to eq(1)
    expect(summary[:reconciled_by_email]).to eq(1)
    expect(existing.reload.provider).to eq("shibboleth")
    expect(existing.uid).to eq("person@example.edu")
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
    File.write(checksum_path, "#{checksum}  legacy_users.ndjson\n")
    File.write(
      manifest_path,
      JSON.pretty_generate(
        {
          generated_at: Time.current.utc.iso8601,
          bundle_file: "legacy_users.ndjson",
          record_count: payloads.length,
          sha256: checksum,
          counts: { "User" => payloads.length }
        }
      )
    )
  end
end
