require "rails_helper"

RSpec.describe Ingest::HealthSummary, type: :service do
  let(:dataset) { create(:dataset) }
  let(:now) { Time.zone.parse("2026-06-08 15:00:00") }

  before do
    allow(IdbConfig).to receive(:fetch).and_call_original
  end

  it "returns nil when there is no latest attempt" do
    expect(described_class.new(dataset: dataset, latest_attempt: nil, now: now).call).to be_nil
  end

  it "reports warning when the latest successful response is stale" do
    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :started,
      response_status: :succeeded,
      response_received_at: now - 2.hours,
      attempt: 1,
      idempotency_key: "health:#{dataset.id}:1"
    )

    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_response_stale_minutes, default: "60").and_return("60")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_lookback_minutes, default: "120").and_return("120")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_alert_threshold, default: "1").and_return("5")

    summary = described_class.new(dataset: dataset, latest_attempt: attempt, now: now).call

    expect(summary[:state]).to eq("warning")
    expect(summary[:freshness_message]).to eq("Latest Medusa response was received 120 minute(s) ago.")
    expect(summary[:alerts]).to include("Latest Medusa response is stale (120 minutes old; threshold 60 minutes).")
  end

  it "reports critical when the latest response failed" do
    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :failed,
      response_received_at: now - 10.minutes,
      attempt: 1,
      idempotency_key: "health:#{dataset.id}:2"
    )

    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_response_stale_minutes, default: "60").and_return("60")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_lookback_minutes, default: "120").and_return("120")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_alert_threshold, default: "1").and_return("5")

    summary = described_class.new(dataset: dataset, latest_attempt: attempt, now: now).call

    expect(summary[:state]).to eq("critical")
    expect(summary[:alerts]).to include("Latest Medusa response reported failure.")
  end

  it "counts orphaned responses by correlation key or payload dataset id" do
    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :started,
      response_status: :succeeded,
      response_received_at: now - 10.minutes,
      attempt: 1,
      idempotency_key: "health:#{dataset.id}:3",
      correlation_key: "dataset.published:#{dataset.id}:1"
    )

    IngestResponseEvent.create!(
      status: :unmatched,
      integration: "ingest",
      correlation_key: "dataset.published:#{dataset.id}:orphan-a",
      received_at: now - 20.minutes,
      payload: { status: "ok" },
      raw_payload: "{}"
    )
    IngestResponseEvent.create!(
      status: :invalid,
      integration: "ingest",
      correlation_key: "other",
      received_at: now - 15.minutes,
      payload: { pass_through: { dataset_id: dataset.id } },
      raw_payload: "{}"
    )

    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_response_stale_minutes, default: "60").and_return("60")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_lookback_minutes, default: "120").and_return("120")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_alert_threshold, default: "1").and_return("2")

    summary = described_class.new(dataset: dataset, latest_attempt: attempt, now: now).call

    expect(summary[:state]).to eq("warning")
    expect(summary[:orphan_count]).to eq(2)
    expect(summary[:alerts]).to include("2 orphaned ingest response(s) in the last 120 minutes (threshold 2).")
  end

  it "normalizes ingest health configuration values" do
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_response_stale_minutes, default: "60").and_return("0")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_lookback_minutes, default: "120").and_return("-5")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_orphan_alert_threshold, default: "1").and_return("-1")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_alerts_enabled, default: "false").and_return("TRUE")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_alert_emails, default: "").and_return(" One@example.edu, two@example.edu ,ONE@example.edu ")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :health_alert_cooldown_minutes, default: "60").and_return("0")

    expect(described_class.stale_minutes).to eq(60)
    expect(described_class.orphan_lookback_minutes).to eq(120)
    expect(described_class.orphan_alert_threshold).to eq(0)
    expect(described_class.alerts_enabled?).to be(true)
    expect(described_class.alert_recipients).to eq([ "one@example.edu", "two@example.edu" ])
    expect(described_class.alert_cooldown_minutes).to eq(60)
  end
end
