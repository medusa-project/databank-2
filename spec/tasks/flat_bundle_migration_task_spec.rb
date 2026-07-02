require "rails_helper"
require "rake"

RSpec.describe "migration:flat_bundle tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_from_dir_task) { Rake::Task["migration:flat_bundle:import_from_dir"] }

  before do
    import_from_dir_task.reenable
  end

  it "builds default paths from DIR, invokes flat importer, and records a flat bundle run" do
    dir = Rails.root.join("tmp", "flat_bundle_spec")
    FileUtils.mkdir_p(dir)
    File.write(dir.join("legacy_datasets.ndjson"), "")
    File.write(dir.join("legacy_datasets.ndjson.sha256"), "")
    File.write(dir.join("manifest.json"), "{}")

    ENV["DIR"] = dir.to_s
    ENV.delete("BUNDLE_FILE")
    ENV.delete("CHECKSUM")
    ENV.delete("CHECKSUM_FILE")
    ENV.delete("MANIFEST")
    ENV.delete("MANIFEST_FILE")
    ENV.delete("REPORT_FILE")
    ENV["DRY_RUN"] = "true"

    importer = instance_double(Migration::FlatBundleImportService)
    allow(Migration::FlatBundleImportService).to receive(:new).and_return(importer)
    allow(importer).to receive(:call).and_return(
      {
        created: 0,
        updated: 0,
        skipped_existing: 0,
        failed: 0,
        would_create: 1,
        would_update: 0,
        processed_count: 1,
        expected_record_count: 1,
        record_counts: {
          datasets: 1,
          datafiles: 0,
          nested_items: 0
        },
        validation_error: nil
      }
    )

    import_from_dir_task.invoke

    expect(Migration::FlatBundleImportService).to have_received(:new).with(
      bundle_path: dir.join("legacy_datasets.ndjson").to_s,
      overwrite: false,
      dry_run: true,
      checksum_path: dir.join("legacy_datasets.ndjson.sha256").to_s,
      manifest_path: dir.join("manifest.json").to_s,
      report_path: dir.join("import_report.json").to_s
    )

    run = MigrationRun.order(:id).last
    expect(run.run_type).to eq("flat_bundle_import")
    expect(run.status).to eq("completed")
    expect(run.processed_count).to eq(1)
    expect(run.expected_count).to eq(1)
  ensure
    ENV.delete("DIR")
    ENV.delete("DRY_RUN")
    FileUtils.rm_rf(dir)
  end
end
