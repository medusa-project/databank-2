require "rails_helper"

RSpec.describe Ingest::RabbitmqResponseConsumer, type: :service do
  let(:logger) { instance_double(ActiveSupport::Logger, warn: nil, error: nil) }
  let(:consumer) { described_class.new(logger: logger) }
  let(:finalizer) { instance_double(Medusa::FinalizeIngestService, call: true) }

  before do
    allow(Medusa::FinalizeIngestService).to receive(:new).and_return(finalizer)
  end

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

  it "handles an IDB ingest success response with medusa_key and echoed correlation context" do
    payload = {
      operation: "ingest",
      status: "ok",
      staging_key: "prefix/test_dir/file.txt",
      item_root_dir: "preservation/root",
      medusa_path: "another/location/content.txt",
      medusa_key: "another/location/content.txt",
      pass_through: { correlation_key: attempt.correlation_key, key: "some value" }
    }.to_json

    expect(consumer.process_payload(payload)).to eq(:matched)
    expect(attempt.reload).to have_attributes(
      status: "succeeded",
      response_status: "succeeded",
      response_staging_key: "prefix/test_dir/file.txt",
      response_target_key: "another/location/content.txt",
      response_payload: JSON.parse(payload)
    )
    expect(attempt.response_received_at).to be_present
    expect(IngestResponseEvent.last).to have_attributes(
      status: "matched",
      correlation_key: attempt.correlation_key,
      external_delivery_attempt_id: attempt.id,
      payload: JSON.parse(payload),
      raw_payload: payload,
      error_message: nil
    )
    expect(Medusa::FinalizeIngestService).to have_received(:new).with(dataset)
    expect(finalizer).to have_received(:call).once
  end

  it "handles an IDB duplicate-file error response with echoed correlation context" do
    error_message = "File with the path already exists, is already scheduled for ingestion, or stating key was blank"
    payload = {
      operation: "ingest",
      status: "error",
      error: error_message,
      staging_key: "prefix/test_dir/file.txt",
      pass_through: { correlation_key: attempt.correlation_key, key: "some value" }
    }.to_json

    expect(consumer.process_payload(payload)).to eq(:matched)
    expect(attempt.reload).to have_attributes(
      status: "failed",
      response_status: "failed",
      error_class: "MedusaResponseError",
      error_message: error_message,
      response_staging_key: "prefix/test_dir/file.txt",
      response_payload: JSON.parse(payload)
    )
    expect(attempt.response_received_at).to be_present
    expect(IngestResponseEvent.last).to have_attributes(
      status: "matched",
      correlation_key: attempt.correlation_key,
      external_delivery_attempt_id: attempt.id,
      payload: JSON.parse(payload),
      raw_payload: payload
    )
    expect(Medusa::FinalizeIngestService).not_to have_received(:new)
    expect(finalizer).not_to have_received(:call)
  end

  it "handles generic Medusa success status and nested pass-through context" do
    payload = {
      status: "success",
      action: "ingest",
      parameters: {},
      pass_through: {
        correlation_key: attempt.correlation_key,
        staging_key: "draft/path",
        target_key: "medusa/path"
      }
    }.to_json

    expect(consumer.process_payload(payload)).to eq(:matched)
    expect(attempt.reload.response_status).to eq("succeeded")
    expect(attempt.response_staging_key).to eq("draft/path")
    expect(attempt.response_target_key).to eq("medusa/path")
    expect(attempt.response_payload).to eq(JSON.parse(payload))
    expect(finalizer).to have_received(:call).once
    expect(IngestResponseEvent.last.raw_payload).to eq(payload)
  end

  it "handles generic Medusa failure status and message" do
    payload = {
      status: "failure",
      message: "Ingest failed",
      parameters: {},
      pass_through: { correlation_key: attempt.correlation_key }
    }.to_json

    expect(consumer.process_payload(payload)).to eq(:matched)
    expect(attempt.reload.response_status).to eq("failed")
    expect(attempt.status).to eq("failed")
    expect(attempt.error_message).to eq("Ingest failed")
    expect(finalizer).not_to have_received(:call)
  end

  %w[idempotency_key staging_key].each do |key|
    it "matches a response using the #{key} correlation fallback" do
      payload = { key => attempt.correlation_key, "status" => "success" }.to_json

      expect(consumer.process_payload(payload)).to eq(:matched)
      expect(attempt.reload.response_status).to eq("succeeded")
    end
  end

  it "prefers the top-level correlation key over other correlation fields" do
    payload = {
      correlation_key: attempt.correlation_key,
      idempotency_key: "not-the-attempt",
      pass_through: { correlation_key: "also-not-the-attempt" },
      staging_key: "different-staging-key",
      status: "success"
    }.to_json

    expect(consumer.process_payload(payload)).to eq(:matched)
    expect(IngestResponseEvent.last.correlation_key).to eq(attempt.correlation_key)
  end

  it "records and logs a response without a correlation key" do
    payload = { status: "success" }.to_json

    expect(consumer.process_payload(payload)).to eq(:unmatched)
    expect(IngestResponseEvent.last).to have_attributes(
      status: "unmatched", correlation_key: nil,
      error_message: "Missing correlation key", raw_payload: payload
    )
    expect(attempt.reload.response_received_at).to be_nil
    expect(logger).to have_received(:warn).with(
      "Ingest::RabbitmqResponseConsumer unmatched response: missing correlation key"
    )
  end

  it "records processing failures as invalid and logs the error" do
    allow(ExternalDeliveryAttempt).to receive(:for_ingest_correlation).and_raise(
      ActiveRecord::ConnectionNotEstablished, "database unavailable"
    )
    payload = { correlation_key: attempt.correlation_key, status: "success" }.to_json

    expect(consumer.process_payload(payload)).to eq(:invalid)
    expect(IngestResponseEvent.last).to have_attributes(
      status: "invalid", error_message: "Processing failure: ActiveRecord::ConnectionNotEstablished",
      raw_payload: payload
    )
    expect(logger).to have_received(:error).with(
      "Ingest::RabbitmqResponseConsumer process_payload failed: ActiveRecord::ConnectionNotEstablished: database unavailable"
    )
  end

  it "logs event persistence failures without changing the unmatched outcome" do
    event = IngestResponseEvent.new
    event.errors.add(:status, "is invalid")
    error = ActiveRecord::RecordInvalid.new(event)
    allow(IngestResponseEvent).to receive(:create!).and_raise(error)

    expect(consumer.process_payload({ status: "success" }.to_json)).to eq(:unmatched)
    expect(logger).to have_received(:error).with(
      "Ingest::RabbitmqResponseConsumer record_event failed: ActiveRecord::RecordInvalid: #{error.message}"
    )
  end

  describe "#consume_batch" do
    let(:queue) { instance_double("Bunny::Queue") }
    let(:channel) { instance_double("Bunny::Channel", ack: nil) }
    let(:session) { instance_double("Bunny::Session", start: nil, open?: true, close: nil) }
    let(:delivery) { double("delivery info", delivery_tag: 42) }

    before do
      bunny_class = Class.new do
        def self.new(_url); end
      end
      stub_const("Bunny", bunny_class)
      allow(Bunny).to receive(:new).with("amqp://broker.example.test").and_return(session)
      allow(session).to receive(:create_channel).and_return(channel)
      allow(channel).to receive(:queue).with("medusa_to_databank", durable: true).and_return(queue)
      allow(queue).to receive(:pop).with(manual_ack: true).and_return([ nil, nil, nil ])
      allow(IdbConfig).to receive(:fetch).and_call_original
      allow(IdbConfig).to receive(:fetch).with(:ingest, :responses_enabled, default: "false").and_return("TRUE")
      allow(IdbConfig).to receive(:fetch).with(:ingest, :rabbitmq_url, default: "").and_return(" amqp://broker.example.test ")
      allow(IdbConfig).to receive(:fetch).with(:ingest, :responses_queue, default: "").and_return(" medusa_to_databank ")
      allow(IdbConfig).to receive(:fetch).with(:ingest, :response_batch_size, default: "50").and_return("3")
    end

    it "enables consumption when configuration and Bunny are available" do
      expect(consumer.enabled?).to be_truthy
    end

    it "accepts a boolean enable flag from YAML or credentials" do
      allow(IdbConfig).to receive(:fetch).with(:ingest, :responses_enabled, default: "false").and_return(true)

      expect(consumer.enabled?).to be_truthy
    end

    {
      responses_enabled: "false",
      rabbitmq_url: " ",
      responses_queue: " "
    }.each do |key, value|
      it "does not connect when #{key} disables consumption" do
        default = key == :responses_enabled ? "false" : ""
        allow(IdbConfig).to receive(:fetch).with(:ingest, key, default: default).and_return(value)

        expect(consumer.enabled?).to be_falsey
        expect(consumer.consume_batch.to_h).to eq(processed: 0, matched: 0, unmatched: 0, invalid: 0)
        expect(Bunny).not_to have_received(:new)
      end
    end

    it "does not connect when the optional Bunny dependency is unavailable" do
      hide_const("Bunny")

      expect(consumer.enabled?).to be_falsey
      expect(consumer.consume_batch.to_h).to eq(processed: 0, matched: 0, unmatched: 0, invalid: 0)
      expect(session).not_to have_received(:start)
    end

    it "stops at an empty queue and closes the connection without acknowledging" do
      expect(consumer.consume_batch.to_h).to eq(processed: 0, matched: 0, unmatched: 0, invalid: 0)
      expect(session).to have_received(:start).once
      expect(channel).to have_received(:queue).with("medusa_to_databank", durable: true)
      expect(queue).to have_received(:pop).with(manual_ack: true).once
      expect(channel).not_to have_received(:ack)
      expect(session).to have_received(:close).once
    end

    it "counts and acknowledges matched, unmatched, and invalid messages using the configured batch size" do
      matched = { status: "success", pass_through: { correlation_key: attempt.correlation_key } }.to_json
      unmatched = { status: "failure", pass_through: { correlation_key: "unknown" } }.to_json
      deliveries = [ 1, 2, 3 ].map { |tag| double("delivery #{tag}", delivery_tag: tag) }
      allow(queue).to receive(:pop).with(manual_ack: true).and_return(
        [ deliveries[0], nil, matched ],
        [ deliveries[1], nil, unmatched ],
        [ deliveries[2], nil, "{not-json" ]
      )

      expect { @result = consumer.consume_batch }.to change(IngestResponseEvent, :count).by(3)
      expect(@result.to_h).to eq(processed: 3, matched: 1, unmatched: 1, invalid: 1)
      expect(attempt.reload.response_status).to eq("succeeded")
      expect(queue).to have_received(:pop).exactly(3).times
      deliveries.each { |info| expect(channel).to have_received(:ack).with(info.delivery_tag).once }
      expect(session).to have_received(:close).once
    end

    it "honors an explicit batch limit and acknowledges only after processing" do
      allow(queue).to receive(:pop).and_return([ delivery, nil, "{}" ])
      expect(consumer).to receive(:process_payload).with("{}").ordered.and_return(:unmatched)
      expect(channel).to receive(:ack).with(42).ordered

      expect(consumer.consume_batch(max_messages: 1).processed).to eq(1)
      expect(queue).to have_received(:pop).once
    end

    [ 0, -1 ].each do |limit|
      it "processes at least one message for a batch limit of #{limit}" do
        allow(queue).to receive(:pop).and_return([ delivery, nil, "{}" ])

        expect(consumer.consume_batch(max_messages: limit).unmatched).to eq(1)
        expect(queue).to have_received(:pop).once
      end
    end

    it "counts a payload without delivery metadata without acknowledging it" do
      allow(queue).to receive(:pop).and_return([ nil, nil, "{}" ])

      expect(consumer.consume_batch(max_messages: 1).unmatched).to eq(1)
      expect(channel).not_to have_received(:ack)
    end

    it "acknowledges a processing failure recorded as invalid" do
      allow(queue).to receive(:pop).and_return(
        [ delivery, nil, { correlation_key: attempt.correlation_key }.to_json ]
      )
      allow(ExternalDeliveryAttempt).to receive(:for_ingest_correlation).and_raise(
        ActiveRecord::ConnectionNotEstablished, "database unavailable"
      )

      expect(consumer.consume_batch(max_messages: 1).invalid).to eq(1)
      expect(channel).to have_received(:ack).with(42)
      expect(IngestResponseEvent.last.status).to eq("invalid")
    end

    it "logs and reraises queue failures while closing the connection" do
      allow(queue).to receive(:pop).and_raise(IOError, "connection lost")

      expect { consumer.consume_batch }.to raise_error(IOError, "connection lost")
      expect(logger).to have_received(:error).with(
        "Ingest::RabbitmqResponseConsumer consume_batch failed: IOError: connection lost"
      )
      expect(channel).not_to have_received(:ack)
      expect(session).to have_received(:close).once
    end

    it "closes the connection when acknowledgment fails" do
      allow(queue).to receive(:pop).and_return([ delivery, nil, "{}" ])
      allow(channel).to receive(:ack).and_raise(IOError, "ack failed")

      expect { consumer.consume_batch }.to raise_error(IOError, "ack failed")
      expect(session).to have_received(:close).once
    end

    it "does not close a session that failed to open" do
      allow(session).to receive(:start).and_raise(IOError, "cannot connect")
      allow(session).to receive(:open?).and_return(false)

      expect { consumer.consume_batch }.to raise_error(IOError, "cannot connect")
      expect(session).not_to have_received(:close)
      expect(session).not_to have_received(:create_channel)
    end

    it "logs and reraises connection construction failures" do
      allow(Bunny).to receive(:new).and_raise(ArgumentError, "invalid connection URL")

      expect { consumer.consume_batch }.to raise_error(ArgumentError, "invalid connection URL")
      expect(logger).to have_received(:error).with(
        "Ingest::RabbitmqResponseConsumer consume_batch failed: ArgumentError: invalid connection URL"
      )
      expect(session).not_to have_received(:close)
    end
  end
end
