require "rails_helper"

RSpec.describe Ingest::RabbitmqResponseConsumer, type: :service do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-7999991",
      title: "Ingest Response Dataset",
      description: "Dataset for ingest response tests",
      owner_uid: "owner-response",
      depositor_name: "Owner Response",
      depositor_email: "owner-response@example.edu",
      publication_state: :published,
      published_at: Time.current,
      identifier: "10.5555/IDB-7999991"
    )
  end

  let!(:attempt) do
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset.id}:#{dataset.published_at.utc.iso8601}",
      correlation_key: "corr-7999991"
    )
  end

  it "applies a successful ingest response" do
    payload = {
      correlation_key: "corr-7999991",
      status: "ok",
      uuid: "medusa-uuid-1",
      target_key: "medusa/path/target"
    }.to_json

    outcome = described_class.new.process_payload(payload)

    expect(outcome).to eq(:matched)
    expect(attempt.reload.response_status).to eq("succeeded")
    expect(attempt.response_uuid).to eq("medusa-uuid-1")
    expect(attempt.response_target_key).to eq("medusa/path/target")
    expect(attempt.response_received_at).to be_present
    event = IngestResponseEvent.order(:created_at).last
    expect(event.status).to eq("matched")
    expect(event.external_delivery_attempt_id).to eq(attempt.id)
  end

  it "marks attempt failed when response reports failure" do
    payload = {
      correlation_key: "corr-7999991",
      status: "error",
      error_message: "Medusa ingest failed"
    }.to_json

    outcome = described_class.new.process_payload(payload)

    expect(outcome).to eq(:matched)
    attempt.reload
    expect(attempt.response_status).to eq("failed")
    expect(attempt.status).to eq("failed")
    expect(attempt.error_class).to eq("MedusaResponseError")
    expect(attempt.error_message).to eq("Medusa ingest failed")
  end

  it "returns unmatched when correlation key is not found" do
    payload = { correlation_key: "missing-correlation", status: "ok" }.to_json

    outcome = described_class.new.process_payload(payload)

    expect(outcome).to eq(:unmatched)
    event = IngestResponseEvent.order(:created_at).last
    expect(event.status).to eq("unmatched")
    expect(event.correlation_key).to eq("missing-correlation")
  end

  it "returns invalid for malformed JSON" do
    outcome = described_class.new.process_payload("{not-json")

    expect(outcome).to eq(:invalid)
    event = IngestResponseEvent.order(:created_at).last
    expect(event.status).to eq("invalid")
  end
end
