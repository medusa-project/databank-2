require "rails_helper"

RSpec.describe ExternalDeliveryAttempt, type: :model do
  let(:dataset) { create(:dataset) }

  it "applies a successful ingest response using direct fields" do
    attempt = described_class.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :started,
      attempt: 1,
      idempotency_key: "publish:#{dataset.id}:1",
      correlation_key: "dataset.published:#{dataset.id}:1"
    )

    fixed_time = Time.zone.parse("2026-06-08 12:00:00")
    allow(Time).to receive(:current).and_return(fixed_time)

    begin
      attempt.apply_ingest_response!(
        "status" => "ok",
        "uuid" => "uuid-123",
        "staging_key" => "staging/key",
        "target_key" => "target/key"
      )

      attempt.reload
      expect(attempt.response_status).to eq("succeeded")
      expect(attempt.status).to eq("started")
      expect(attempt.response_uuid).to eq("uuid-123")
      expect(attempt.response_staging_key).to eq("staging/key")
      expect(attempt.response_target_key).to eq("target/key")
      expect(attempt.response_received_at).to eq(fixed_time)
      expect(attempt.response_payload).to include("status" => "ok")
    ensure
      allow(Time).to receive(:current).and_call_original
    end
  end

  it "marks failed responses and extracts fallback fields" do
    attempt = described_class.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :started,
      attempt: 1,
      idempotency_key: "publish:#{dataset.id}:1",
      correlation_key: "dataset.published:#{dataset.id}:1"
    )

    attempt.apply_ingest_response!(
      {
        "request_status" => "failed",
        "medusa_uuid" => "uuid-456",
        "medusa_key" => "medusa/key",
        "error" => "response failed",
        "pass_through" => { "staging_key" => "fallback/staging" }
      }
    )

    attempt.reload
    expect(attempt.response_status).to eq("failed")
    expect(attempt.status).to eq("failed")
    expect(attempt.error_class).to eq("MedusaResponseError")
    expect(attempt.error_message).to eq("response failed")
    expect(attempt.response_uuid).to eq("uuid-456")
    expect(attempt.response_staging_key).to eq("fallback/staging")
    expect(attempt.response_target_key).to eq("medusa/key")
  end

  it "uses a default error message when a failure payload has no message" do
    attempt = described_class.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :started,
      attempt: 1,
      idempotency_key: "publish:#{dataset.id}:1"
    )

    attempt.apply_ingest_response!("status" => "failed")

    expect(attempt.reload.error_message).to eq("Medusa ingest response reported failure")
  end

  it "finds only succeeded attempts for an idempotency key" do
    success = described_class.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: "publish:#{dataset.id}:1"
    )
    described_class.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 2,
      idempotency_key: "publish:#{dataset.id}:1"
    )

    expect(described_class.succeeded_for(integration: :ingest, event_name: "dataset.published", idempotency_key: "publish:#{dataset.id}:1")).to contain_exactly(success)
  end

  it "orders ingest correlation attempts newest first" do
    older = described_class.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :started,
      attempt: 1,
      idempotency_key: "publish:#{dataset.id}:1",
      correlation_key: "dataset.published:#{dataset.id}:abc",
      created_at: 2.hours.ago
    )
    newer = described_class.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :started,
      attempt: 2,
      idempotency_key: "publish:#{dataset.id}:2",
      correlation_key: "dataset.published:#{dataset.id}:abc",
      created_at: 1.hour.ago
    )

    expect(described_class.for_ingest_correlation("dataset.published:#{dataset.id}:abc")).to eq([ newer, older ])
  end
end
