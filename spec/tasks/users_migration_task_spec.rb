require "rails_helper"
require "rake"

RSpec.describe "migration:users tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_from_dir_task) { Rake::Task["migration:users:import_from_dir"] }

  before do
    import_from_dir_task.reenable
  end

  it "builds bundle/checksum/manifest paths from DIR and invokes importer" do
    dir = Rails.root.join("tmp", "users_bundle")
    FileUtils.mkdir_p(dir)
    File.write(dir.join("legacy_users.ndjson"), "")
    File.write(dir.join("legacy_users.ndjson.sha256"), "")
    File.write(dir.join("manifest.json"), "{}")

    ENV["DIR"] = dir.to_s
    ENV.delete("BUNDLE_FILE")
    ENV.delete("CHECKSUM")
    ENV.delete("CHECKSUM_FILE")
    ENV.delete("MANIFEST")
    ENV.delete("MANIFEST_FILE")
    ENV["DRY_RUN"] = "true"

    importer = instance_double(Migration::UsersBundleImportService)
    allow(Migration::UsersBundleImportService).to receive(:new).and_return(importer)
    allow(importer).to receive(:call).and_return(
      {
        created: 0,
        updated: 0,
        skipped_existing: 0,
        failed: 0,
        would_create: 1,
        would_update: 0,
        skipped_unsupported_role: 0,
        skipped_invalid_identity: 0,
        reconciled_by_email: 0
      }
    )

    import_from_dir_task.invoke

    expect(Migration::UsersBundleImportService).to have_received(:new).with(
      bundle_path: dir.join("legacy_users.ndjson").to_s,
      dry_run: true,
      checksum_path: dir.join("legacy_users.ndjson.sha256").to_s,
      manifest_path: dir.join("manifest.json").to_s,
      report_path: dir.join("import_report.json").to_s
    )
  ensure
    ENV.delete("DIR")
    ENV.delete("DRY_RUN")
    FileUtils.rm_rf(dir)
  end
end
