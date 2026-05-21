require "rails_helper"

RSpec.describe Migration::RunRecorder do
  it "records start and finish state for a bundle import" do
    recorder = described_class.new(
      run_type: "bundle_import",
      label: "nightly-rehearsal",
      bundle_path: "/tmp/bundle.ndjson",
      checksum_path: "/tmp/bundle.ndjson.sha256",
      manifest_path: "/tmp/manifest.json",
      source_since: Time.zone.parse("2026-01-01T00:00:00Z"),
      source_until: Time.zone.parse("2026-02-01T00:00:00Z")
    )

    run = recorder.start!

    recorder.finish!(
      run: run,
      summary: {
        bundle_path: "/tmp/bundle.ndjson",
        created: 3,
        updated: 2,
        skipped_existing: 1,
        failed: 0,
        would_create: 0,
        would_update: 0,
        processed_count: 6,
        expected_record_count: 6,
        checksum: "abc123",
        source_since: "2026-01-01T00:00:00Z",
        source_until: "2026-02-01T00:00:00Z"
      }
    )

    run.reload
    expect(run.status).to eq("completed")
    expect(run.created_count).to eq(3)
    expect(run.updated_count).to eq(2)
    expect(run.skipped_count).to eq(1)
    expect(run.failed_count).to eq(0)
    expect(run.processed_count).to eq(6)
    expect(run.expected_count).to eq(6)
  end
end
