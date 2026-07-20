require "rails_helper"
require "rake"

RSpec.describe "migration:flat_bundle tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_from_dir_task) { Rake::Task["migration:flat_bundle:import_from_dir"] }
  let(:import_in_chunks_task) { Rake::Task["migration:flat_bundle:import_in_chunks"] }

  before do
    import_from_dir_task.reenable
    import_in_chunks_task.reenable
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

  it "loops chunk imports until checkpoint indicates completion" do
    dir = Rails.root.join("tmp", "flat_bundle_chunk_spec")
    checkpoint_path = dir.join("chunk.checkpoint.json")
    report_path = dir.join("chunk.report.json")
    FileUtils.mkdir_p(dir)

    ENV["DIR"] = dir.to_s
    ENV["BUNDLE_FILE"] = "legacy_datasets.ndjson"
    ENV["CHECKPOINT_FILE"] = checkpoint_path.to_s
    ENV["REPORT_FILE"] = report_path.to_s
    ENV["MAX_RECORDS"] = "10"
    ENV["MAX_ITERATIONS"] = "5"
    ENV["MAX_MINUTES"] = "5"
    ENV["MAX_CONSECUTIVE_FAILURES"] = "5"
    ENV["MAX_STALLED_RUNS"] = "2"
    ENV["RESUME_OVERLAP_LINES"] = "0"

    import_calls = 0
    allow_any_instance_of(Migration::FlatBundleImportService).to receive(:call) do
      import_calls += 1
      payload = if import_calls == 1
        {
          "next_resume_from_line" => 101,
          "stopped_early" => true,
          "summary" => { "validation_error" => nil, "failed" => 0, "datasets" => 1, "datafiles" => 0, "nested_items" => 0 }
        }
      else
        {
          "next_resume_from_line" => 202,
          "stopped_early" => false,
          "summary" => { "validation_error" => nil, "failed" => 0, "datasets" => 1, "datafiles" => 0, "nested_items" => 0 }
        }
      end
      File.write(checkpoint_path, JSON.pretty_generate(payload))

      {
        created: 0,
        updated: 0,
        skipped_existing: 0,
        failed: 0,
        would_create: 0,
        would_update: 0,
        processed_count: 10,
        expected_record_count: 10,
        record_counts: { datasets: 1, datafiles: 0, nested_items: 0 },
        validation_error: nil,
        stopped_early: payload["stopped_early"],
        next_resume_from_line: payload["next_resume_from_line"]
      }
    end

    import_in_chunks_task.invoke

    expect(import_calls).to eq(2)
  ensure
    %w[DIR BUNDLE_FILE CHECKPOINT_FILE REPORT_FILE MAX_RECORDS MAX_ITERATIONS MAX_MINUTES MAX_CONSECUTIVE_FAILURES MAX_STALLED_RUNS RESUME_OVERLAP_LINES].each { |k| ENV.delete(k) }
    FileUtils.rm_rf(dir)
  end

  it "stops chunk loop when checkpoint progress stalls" do
    dir = Rails.root.join("tmp", "flat_bundle_chunk_stall_spec")
    checkpoint_path = dir.join("chunk.checkpoint.json")
    report_path = dir.join("chunk.report.json")
    FileUtils.mkdir_p(dir)

    ENV["DIR"] = dir.to_s
    ENV["BUNDLE_FILE"] = "legacy_datasets.ndjson"
    ENV["CHECKPOINT_FILE"] = checkpoint_path.to_s
    ENV["REPORT_FILE"] = report_path.to_s
    ENV["MAX_RECORDS"] = "10"
    ENV["MAX_ITERATIONS"] = "10"
    ENV["MAX_MINUTES"] = "5"
    ENV["MAX_CONSECUTIVE_FAILURES"] = "5"
    ENV["MAX_STALLED_RUNS"] = "2"
    ENV["RESUME_OVERLAP_LINES"] = "0"

    import_calls = 0
    allow_any_instance_of(Migration::FlatBundleImportService).to receive(:call) do
      import_calls += 1
      File.write(
        checkpoint_path,
        JSON.pretty_generate(
          {
            "next_resume_from_line" => 100,
            "stopped_early" => true,
            "summary" => { "validation_error" => nil, "failed" => 0, "datasets" => 0, "datafiles" => 0, "nested_items" => 0 }
          }
        )
      )

      {
        created: 0,
        updated: 0,
        skipped_existing: 0,
        failed: 0,
        would_create: 0,
        would_update: 0,
        processed_count: 10,
        expected_record_count: 10,
        record_counts: { datasets: 0, datafiles: 0, nested_items: 0 },
        validation_error: nil,
        stopped_early: true,
        next_resume_from_line: 100
      }
    end

    import_in_chunks_task.invoke

    expect(import_calls).to eq(3)
  ensure
    %w[DIR BUNDLE_FILE CHECKPOINT_FILE REPORT_FILE MAX_RECORDS MAX_ITERATIONS MAX_MINUTES MAX_CONSECUTIVE_FAILURES MAX_STALLED_RUNS RESUME_OVERLAP_LINES].each { |k| ENV.delete(k) }
    FileUtils.rm_rf(dir)
  end
end
