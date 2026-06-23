require "rails_helper"

RSpec.describe Ingest::SendHealthAlertsJob, type: :job do
  include ActiveJob::TestHelper

  let(:dataset) do
    Dataset.create!(
      key: "IDB-5999999",
      title: "Health Alert Dataset",
      description: "Health alert tests",
      owner_uid: "owner-health",
      depositor_name: "Owner Health",
      depositor_email: "owner-health@example.edu",
      publication_state: :published,
      published_at: Time.current,
      identifier: "10.5555/IDB-5999999"
    )
  end

  before do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  it "sends alert emails for datasets with threshold violations" do
    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :succeeded,
      response_received_at: 3.hours.ago,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset.id}:health-job"
    )

    IngestResponseEvent.create!(
      status: :unmatched,
      integration: "ingest",
      correlation_key: "dataset.published:#{dataset.id}:orphan-job",
      received_at: Time.current,
      payload: { status: "ok", pass_through: { dataset_id: dataset.id } },
      raw_payload: "{}",
      error_message: "No matching delivery attempt"
    )

    stub_ingest_config(
      health_alerts_enabled: "true",
      health_alert_emails: "alerts@example.edu",
      health_alert_cooldown_minutes: "60",
      health_response_stale_minutes: "60",
      health_orphan_lookback_minutes: "120",
      health_orphan_alert_threshold: "1"
    )

    allow_any_instance_of(described_class).to receive(:latest_attempts_by_dataset).and_return(
      { dataset.id => attempt }
    )

    expect do
      described_class.perform_now
    end.to have_enqueued_mail(IngestHealthMailer, :dataset_alert)
  end

  it "does not re-send alert during cooldown window" do
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :failed,
      response_received_at: 2.hours.ago,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset.id}:cooldown"
    )

    stub_ingest_config(
      health_alerts_enabled: "true",
      health_alert_emails: "alerts@example.edu",
      health_alert_cooldown_minutes: "60",
      health_response_stale_minutes: "60",
      health_orphan_lookback_minutes: "120",
      health_orphan_alert_threshold: "1"
    )

    allow(Rails.cache).to receive(:read).and_return(false, true)
    allow(Rails.cache).to receive(:write)

    described_class.perform_now
    clear_enqueued_jobs

    expect do
      described_class.perform_now
    end.not_to have_enqueued_mail(IngestHealthMailer, :dataset_alert)
  end

  it "skips when health alerts are disabled" do
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :failed,
      response_received_at: 2.hours.ago,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset.id}:disabled"
    )

    stub_ingest_config(
      health_alerts_enabled: "false",
      health_alert_emails: "alerts@example.edu",
      health_alert_cooldown_minutes: "60",
      health_response_stale_minutes: "60",
      health_orphan_lookback_minutes: "120",
      health_orphan_alert_threshold: "1"
    )

    expect do
      described_class.perform_now
    end.not_to have_enqueued_mail(IngestHealthMailer, :dataset_alert)
  end

  def stub_ingest_config(overrides)
    defaults = {
      health_alerts_enabled: "false",
      health_alert_emails: "",
      health_alert_cooldown_minutes: "60",
      health_response_stale_minutes: "60",
      health_orphan_lookback_minutes: "120",
      health_orphan_alert_threshold: "1"
    }

    config = defaults.merge(overrides)

    allow(IdbConfig).to receive(:fetch).and_call_original
    config.each do |key, value|
      allow(IdbConfig).to receive(:fetch).with(:ingest, key, default: anything).and_return(value)
    end
  end
end
