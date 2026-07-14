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

  it "retries finish on transient database errors and eventually succeeds" do
    recorder = described_class.new(run_type: "bundle_import")
    run = recorder.start!

    attempts = 0
    allow(run).to receive(:update!) do
      attempts += 1
      raise ActiveRecord::ConnectionNotEstablished, "database system is in recovery mode" if attempts == 1

      true
    end

    allow(recorder).to receive(:sleep)

    result = recorder.finish!(
      run: run,
      summary: {
        created: 1,
        updated: 0,
        skipped_existing: 0,
        failed: 0,
        would_create: 0,
        would_update: 0,
        processed_count: 1,
        expected_record_count: 1
      }
    )

    expect(result).to be_truthy
    expect(attempts).to eq(2)
    expect(recorder).to have_received(:sleep).once
  end

  it "does not raise if finish retries are exhausted by transient database errors" do
    recorder = described_class.new(run_type: "bundle_import")
    run = recorder.start!

    allow(run).to receive(:update!).and_raise(ActiveRecord::ConnectionNotEstablished, "database system is in recovery mode")
    allow(recorder).to receive(:sleep)

    expect do
      recorder.finish!(
        run: run,
        summary: {
          created: 0,
          updated: 0,
          skipped_existing: 0,
          failed: 0,
          would_create: 0,
          would_update: 0,
          processed_count: 0,
          expected_record_count: 0
        }
      )
    end.not_to raise_error
  end
end
