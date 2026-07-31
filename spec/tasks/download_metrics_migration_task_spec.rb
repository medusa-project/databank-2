require "rails_helper"
require "rake"

RSpec.describe "migration:download_metrics tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_from_dir_task) { Rake::Task["migration:download_metrics:import_from_dir"] }
  let(:import_in_chunks_task) { Rake::Task["migration:download_metrics:import_in_chunks"] }

  before do
    import_from_dir_task.reenable
    import_in_chunks_task.reenable
  end

  def write_bundle_files(dir:, lines:, manifest_overrides: {})
    bundle_path = dir.join("legacy_download_metrics.ndjson")
    bundle_body = lines.map { |line| JSON.generate(line) }.join("\n") + "\n"
    checksum = Digest::SHA256.hexdigest(bundle_body)

    File.write(bundle_path, bundle_body)
    File.write(dir.join("legacy_download_metrics.ndjson.sha256"), "#{checksum}  legacy_download_metrics.ndjson\n")
    File.write(
      dir.join("manifest.json"),
      JSON.pretty_generate(
        {
          generated_at: Time.current.utc.iso8601,
          bundle_file: "legacy_download_metrics.ndjson",
          record_count: lines.length,
          counts: {
            "DatasetDownloadTally" => lines.count { |line| line[:type] == "DatasetDownloadTally" || line["type"] == "DatasetDownloadTally" },
            "FileDownloadTally" => lines.count { |line| line[:type] == "FileDownloadTally" || line["type"] == "FileDownloadTally" },
            "DayFileDownload" => lines.count { |line| line[:type] == "DayFileDownload" || line["type"] == "DayFileDownload" }
          },
          sha256: checksum,
          format_version: 1
        }.merge(manifest_overrides)
      )
    )

    bundle_path
  end

  it "imports dataset, file, and day download records from a legacy bundle" do
    dir = Rails.root.join("tmp", "download_metrics_bundle_spec")
    FileUtils.mkdir_p(dir)
    report_path = dir.join("download_metrics_import_report.json")

    lines = [
      {
        type: "DatasetDownloadTally",
        attributes: {
          dataset_key: "IDB-0000001",
          doi: "10.5555/IDB-0000001",
          download_date: "2026-01-01",
          tally: 4,
          created_at: "2026-01-01T10:00:00Z",
          updated_at: "2026-01-01T10:00:00Z"
        }
      },
      {
        type: "FileDownloadTally",
        attributes: {
          file_web_id: "file-1",
          filename: "example.csv",
          dataset_key: "IDB-0000001",
          doi: "10.5555/IDB-0000001",
          download_date: "2026-01-01",
          tally: 7,
          created_at: "2026-01-01T10:00:00Z",
          updated_at: "2026-01-01T10:00:00Z"
        }
      },
      {
        type: "DayFileDownload",
        attributes: {
          ip_address: "127.0.0.1",
          file_web_id: "file-1",
          filename: "example.csv",
          dataset_key: "IDB-0000001",
          doi: "10.5555/IDB-0000001",
          download_date: "2026-01-01",
          created_at: "2026-01-01T10:00:00Z",
          updated_at: "2026-01-01T10:00:00Z"
        }
      }
    ]

    write_bundle_files(
      dir: dir,
      lines: lines,
      manifest_overrides: {
        include_tests: false,
        since: "2026-01-01T00:00:00Z",
        until: "2026-02-01T00:00:00Z"
      }
    )

    FileDownloadTally.create!(file_web_id: "file-1", download_date: Date.new(2026, 1, 1), tally: 2, dataset_key: "IDB-0000001")

    ENV["DIR"] = dir.to_s
    ENV.delete("BUNDLE_FILE")
    ENV.delete("CHECKSUM")
    ENV.delete("CHECKSUM_FILE")
    ENV.delete("MANIFEST")
    ENV.delete("MANIFEST_FILE")
    ENV.delete("DRY_RUN")
    ENV["REPORT_FILE"] = report_path.to_s

    expect {
      import_from_dir_task.invoke
    }.to change(DatasetDownloadTally, :count).by(1).and change(DayFileDownload, :count).by(1)

    expect(FileDownloadTally.find_by!(file_web_id: "file-1", download_date: Date.new(2026, 1, 1)).tally).to eq(7)
    expect(DatasetDownloadTally.find_by!(dataset_key: "IDB-0000001", download_date: Date.new(2026, 1, 1)).doi).to eq("10.5555/IDB-0000001")
    expect(DayFileDownload.find_by!(file_web_id: "file-1", download_date: Date.new(2026, 1, 1), ip_address: "127.0.0.1").dataset_key).to eq("IDB-0000001")
    latest_run = MigrationRun.order(:id).last
    expect(latest_run.run_type).to eq("download_metrics_bundle_import")
    expect(latest_run.validation_error).to be_nil

    report_payload = JSON.parse(File.read(report_path))
    report_summary = report_payload.fetch("summary")
    expect(report_summary["manifest_format_version"]).to eq(1)
    expect(report_summary["include_tests"]).to eq(false)
    expect(report_summary["since"]).to eq("2026-01-01T00:00:00Z")
    expect(report_summary["until"]).to eq("2026-02-01T00:00:00Z")
  ensure
    ENV.delete("DIR")
    ENV.delete("DRY_RUN")
    ENV.delete("REPORT_FILE")
    FileUtils.rm_rf(dir)
  end

  it "rejects unsupported legacy download metrics bundle format versions" do
    dir = Rails.root.join("tmp", "download_metrics_bundle_invalid_format_spec")
    FileUtils.mkdir_p(dir)

    lines = [
      {
        type: "DatasetDownloadTally",
        attributes: {
          legacy_id: 99,
          dataset_key: "IDB-0000009",
          doi: "10.5555/IDB-0000009",
          download_date: "2026-01-09",
          tally: 1,
          created_at: "2026-01-09T10:00:00Z",
          updated_at: "2026-01-09T10:00:00Z"
        }
      }
    ]

    write_bundle_files(dir: dir, lines: lines, manifest_overrides: { format_version: 2 })

    ENV["DIR"] = dir.to_s
    ENV.delete("BUNDLE_FILE")
    ENV.delete("CHECKSUM")
    ENV.delete("CHECKSUM_FILE")
    ENV.delete("MANIFEST")
    ENV.delete("MANIFEST_FILE")
    ENV.delete("DRY_RUN")

    expect {
      import_from_dir_task.invoke
    }.to raise_error(ArgumentError, /unsupported download metrics bundle format_version/)

    latest_run = MigrationRun.order(:id).last
    expect(latest_run.run_type).to eq("download_metrics_bundle_import")
    expect(latest_run.validation_error).to eq("unsupported download metrics bundle format_version")
  ensure
    ENV.delete("DIR")
    ENV.delete("DRY_RUN")
    FileUtils.rm_rf(dir)
  end

  it "imports download metrics in resumable chunks until completion" do
    dir = Rails.root.join("tmp", "download_metrics_chunk_spec")
    FileUtils.mkdir_p(dir)

    lines = 5.times.map do |index|
      {
        type: "DatasetDownloadTally",
        attributes: {
          dataset_key: "IDB-CHUNK-#{index + 1}",
          doi: "10.5555/IDB-CHUNK-#{index + 1}",
          download_date: "2026-01-#{format('%02d', index + 1)}",
          tally: index + 1,
          created_at: "2026-01-01T10:00:00Z",
          updated_at: "2026-01-01T10:00:00Z"
        }
      }
    end

    write_bundle_files(dir: dir, lines: lines)

    checkpoint_path = dir.join("download_metrics_import.checkpoint.json")
    report_path = dir.join("download_metrics_chunk.report.json")

    ENV["DIR"] = dir.to_s
    ENV["MAX_RECORDS"] = "2"
    ENV["MAX_ITERATIONS"] = "10"
    ENV["MAX_MINUTES"] = "10"
    ENV["CHECKPOINT_FILE"] = checkpoint_path.to_s
    ENV["REPORT_FILE"] = report_path.to_s
    ENV["RESUME_OVERLAP_LINES"] = "0"
    ENV["LOCK_FILE"] = dir.join("download_metrics_import.lock").to_s
    ENV.delete("DRY_RUN")

    expect {
      import_in_chunks_task.invoke
    }.to change(DatasetDownloadTally, :count).by(5)

    checkpoint = JSON.parse(File.read(checkpoint_path))
    expect(checkpoint["stopped_early"]).to eq(false)
    expect(checkpoint["next_resume_from_line"]).to be >= 6
  ensure
    %w[
      DIR
      MAX_RECORDS
      MAX_ITERATIONS
      MAX_MINUTES
      CHECKPOINT_FILE
      REPORT_FILE
      RESUME_OVERLAP_LINES
      LOCK_FILE
      DRY_RUN
    ].each { |key| ENV.delete(key) }
    FileUtils.rm_rf(dir)
  end

  it "respects max iteration ceiling and can stop before full completion" do
    dir = Rails.root.join("tmp", "download_metrics_chunk_ceiling_spec")
    FileUtils.mkdir_p(dir)

    lines = 6.times.map do |index|
      {
        type: "DatasetDownloadTally",
        attributes: {
          dataset_key: "IDB-CEIL-#{index + 1}",
          doi: "10.5555/IDB-CEIL-#{index + 1}",
          download_date: "2026-02-#{format('%02d', index + 1)}",
          tally: 1,
          created_at: "2026-02-01T10:00:00Z",
          updated_at: "2026-02-01T10:00:00Z"
        }
      }
    end

    write_bundle_files(dir: dir, lines: lines)

    checkpoint_path = dir.join("download_metrics_import.checkpoint.json")

    ENV["DIR"] = dir.to_s
    ENV["MAX_RECORDS"] = "2"
    ENV["MAX_ITERATIONS"] = "1"
    ENV["MAX_MINUTES"] = "10"
    ENV["CHECKPOINT_FILE"] = checkpoint_path.to_s
    ENV["RESUME_OVERLAP_LINES"] = "0"
    ENV["LOCK_FILE"] = dir.join("download_metrics_import.lock").to_s
    ENV.delete("DRY_RUN")

    expect {
      import_in_chunks_task.invoke
    }.to change(DatasetDownloadTally, :count).by(2)

    checkpoint = JSON.parse(File.read(checkpoint_path))
    expect(checkpoint["stopped_early"]).to eq(true)
    expect(checkpoint["next_resume_from_line"]).to eq(3)
  ensure
    %w[
      DIR
      MAX_RECORDS
      MAX_ITERATIONS
      MAX_MINUTES
      CHECKPOINT_FILE
      REPORT_FILE
      RESUME_OVERLAP_LINES
      LOCK_FILE
      DRY_RUN
    ].each { |key| ENV.delete(key) }
    FileUtils.rm_rf(dir)
  end

  it "fails fast when chunked import lock is already held" do
    dir = Rails.root.join("tmp", "download_metrics_chunk_lock_spec")
    FileUtils.mkdir_p(dir)

    lines = [
      {
        type: "DatasetDownloadTally",
        attributes: {
          dataset_key: "IDB-LOCK-1",
          doi: "10.5555/IDB-LOCK-1",
          download_date: "2026-03-01",
          tally: 1,
          created_at: "2026-03-01T10:00:00Z",
          updated_at: "2026-03-01T10:00:00Z"
        }
      }
    ]
    write_bundle_files(dir: dir, lines: lines)

    lock_path = dir.join("download_metrics_import.lock")
    held_lock = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
    expect(held_lock.flock(File::LOCK_EX | File::LOCK_NB)).to eq(0)

    ENV["DIR"] = dir.to_s
    ENV["LOCK_FILE"] = lock_path.to_s
    ENV.delete("DRY_RUN")

    expect {
      import_in_chunks_task.invoke
    }.to raise_error(/already running/)
  ensure
    %w[
      DIR
      MAX_RECORDS
      MAX_ITERATIONS
      MAX_MINUTES
      CHECKPOINT_FILE
      REPORT_FILE
      RESUME_OVERLAP_LINES
      LOCK_FILE
      DRY_RUN
    ].each { |key| ENV.delete(key) }
    if defined?(held_lock) && held_lock
      held_lock.flock(File::LOCK_UN)
      held_lock.close
    end
    FileUtils.rm_rf(dir)
  end
end
