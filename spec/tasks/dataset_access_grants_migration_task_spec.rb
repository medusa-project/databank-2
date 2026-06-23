require "rails_helper"
require "rake"

RSpec.describe "migration:dataset_access_grants tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_from_dir_task) { Rake::Task["migration:dataset_access_grants:import_from_dir"] }

  before do
    import_from_dir_task.reenable
  end

  it "accepts bundles whose manifest count matches lines even when rows fail validation" do
    dir = Rails.root.join("tmp", "dataset_access_grants_bundle_spec")
    FileUtils.mkdir_p(dir)

    lines = [
      {
        type: "DatasetAccessGrant",
        attributes: {
          dataset_key: "IDB-4044044",
          email: "reader@example.edu",
          access_level: "viewer"
        }
      }
    ]

    bundle_path = dir.join("legacy_dataset_access_grants.ndjson")
    bundle_body = lines.map { |line| JSON.generate(line) }.join("\n") + "\n"
    File.write(bundle_path, bundle_body)

    checksum = Digest::SHA256.hexdigest(bundle_body)
    File.write(dir.join("legacy_dataset_access_grants.ndjson.sha256"), "#{checksum}  legacy_dataset_access_grants.ndjson\n")
    File.write(
      dir.join("manifest.json"),
      JSON.pretty_generate(
        {
          generated_at: Time.current.utc.iso8601,
          bundle_file: "legacy_dataset_access_grants.ndjson",
          record_count: 1,
          counts: {
            "DatasetAccessGrant" => 1,
            "viewer" => 1,
            "editor" => 0
          },
          sha256: checksum,
          format_version: 1
        }
      )
    )

    ENV["DIR"] = dir.to_s
    ENV.delete("BUNDLE_FILE")
    ENV.delete("CHECKSUM")
    ENV.delete("CHECKSUM_FILE")
    ENV.delete("MANIFEST")
    ENV.delete("MANIFEST_FILE")
    ENV.delete("DRY_RUN")

    expect { import_from_dir_task.invoke }.not_to raise_error

    run = MigrationRun.order(:id).last
    expect(run.run_type).to eq("dataset_access_grants_bundle_import")
    expect(run.failed_count).to eq(1)
    expect(run.processed_count).to eq(1)
    expect(run.expected_count).to eq(1)
    expect(run.status).to eq("failed")
    expect(run.details.fetch("validation_error", nil)).to be_nil
  ensure
    ENV.delete("DIR")
    ENV.delete("DRY_RUN")
    FileUtils.rm_rf(dir)
  end
end
