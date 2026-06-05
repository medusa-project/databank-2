require "rails_helper"
require "rake"

RSpec.describe "migration:download_metrics tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_from_dir_task) { Rake::Task["migration:download_metrics:import_from_dir"] }

  before do
    import_from_dir_task.reenable
  end

  it "imports dataset, file, and day download records from a legacy bundle" do
    dir = Rails.root.join("tmp", "download_metrics_bundle_spec")
    FileUtils.mkdir_p(dir)

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

    bundle_path = dir.join("legacy_download_metrics.ndjson")
    bundle_body = lines.map { |line| JSON.generate(line) }.join("\n") + "\n"
    File.write(bundle_path, bundle_body)

    checksum = Digest::SHA256.hexdigest(bundle_body)
    File.write(dir.join("legacy_download_metrics.ndjson.sha256"), "#{checksum}  legacy_download_metrics.ndjson\n")
    File.write(
      dir.join("manifest.json"),
      JSON.pretty_generate(
        {
          generated_at: Time.current.utc.iso8601,
          bundle_file: "legacy_download_metrics.ndjson",
          record_count: 3,
          counts: {
            "DatasetDownloadTally" => 1,
            "FileDownloadTally" => 1,
            "DayFileDownload" => 1
          },
          sha256: checksum,
          format_version: 1
        }
      )
    )

    FileDownloadTally.create!(file_web_id: "file-1", download_date: Date.new(2026, 1, 1), tally: 2, dataset_key: "IDB-0000001")

    ENV["DIR"] = dir.to_s
    ENV.delete("BUNDLE_FILE")
    ENV.delete("CHECKSUM")
    ENV.delete("CHECKSUM_FILE")
    ENV.delete("MANIFEST")
    ENV.delete("MANIFEST_FILE")
    ENV.delete("DRY_RUN")

    expect {
      import_from_dir_task.invoke
    }.to change(DatasetDownloadTally, :count).by(1).and change(DayFileDownload, :count).by(1)

    expect(FileDownloadTally.find_by!(file_web_id: "file-1", download_date: Date.new(2026, 1, 1)).tally).to eq(7)
    expect(DatasetDownloadTally.find_by!(dataset_key: "IDB-0000001", download_date: Date.new(2026, 1, 1)).doi).to eq("10.5555/IDB-0000001")
    expect(DayFileDownload.find_by!(file_web_id: "file-1", download_date: Date.new(2026, 1, 1), ip_address: "127.0.0.1").dataset_key).to eq("IDB-0000001")
    expect(MigrationRun.order(:id).last.run_type).to eq("download_metrics_bundle_import")
  ensure
    ENV.delete("DIR")
    ENV.delete("DRY_RUN")
    FileUtils.rm_rf(dir)
  end
end
