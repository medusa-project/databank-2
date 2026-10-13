require "rails_helper"

RSpec.describe Ingest::RabbitmqEventPublisher, type: :service do
  let(:logger) { instance_double(ActiveSupport::Logger, warn: nil) }
  let(:publisher) { described_class.new(logger: logger) }
  let(:exchange) { instance_double(Bunny::Exchange, publish: nil) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:channel) { instance_double(Bunny::Channel, confirm_select: nil, wait_for_confirms: true) }
  let(:session) { instance_double(Bunny::Session, start: nil, open?: true, close: nil) }
  let(:draft_root) { instance_double(StorageManager.instance.draft_root.class, name: "draft", prefix: "uploads/") }
  let(:dataset) { create(:dataset, key: "IDB-7333333") }
  let(:datafile) do
    create(:datafile, dataset: dataset, attach_binary: false, binary_name: "analysis.csv",
      storage_root: "draft", storage_key: "source/analysis.csv")
  end

  before do
    allow(IdbConfig).to receive(:fetch).and_call_original
    allow(IdbConfig).to receive(:fetch).with(:ingest, :events_enabled, default: "false").and_return("true")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :rabbitmq_url, default: "").and_return(" amqp://broker.example.test ")
    allow(IdbConfig).to receive(:fetch).with(:ingest, :requests_queue, default: "").and_return(" idb_to_medusa ")
    allow(Bunny).to receive(:new).with("amqp://broker.example.test").and_return(session)
    allow(session).to receive(:create_channel).and_return(channel)
    allow(channel).to receive(:queue).with("idb_to_medusa", durable: true).and_return(queue)
    allow(channel).to receive(:default_exchange).and_return(exchange)
    allow(StorageManager.instance).to receive(:draft_root).and_return(draft_root)
    allow(StorageManager.instance.root_set).to receive(:at).with("draft").and_return(draft_root)
    allow(draft_root).to receive(:exist?).with("source/analysis.csv").and_return(true)
  end

  it "sends a confirmed file-ingest request directly to Medusa's durable queue" do
    expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(true)
    expect(exchange).to have_received(:publish) do |raw_payload, options|
      expect(options).to eq(
        routing_key: "idb_to_medusa", content_type: "application/json", persistent: true
      )
      expect(JSON.parse(raw_payload)).to eq(
        "operation" => "ingest",
        "staging_key" => "uploads/source/analysis.csv",
        "target_key" => "#{dataset.key}/analysis.csv",
        "pass_through" => {
          "dataset_id" => dataset.id,
          "dataset_key" => dataset.key,
          "datafile_id" => datafile.id,
          "datafile_web_id" => datafile.web_id,
          "correlation_key" => "corr-123"
        }
      )
    end

    expect(channel).to have_received(:queue).with("idb_to_medusa", durable: true)
    expect(channel).to have_received(:confirm_select)
    expect(channel).to have_received(:wait_for_confirms)
    expect(session).to have_received(:close).once
  end

  it "accepts a boolean enable flag from YAML or credentials" do
    allow(IdbConfig).to receive(:fetch).with(:ingest, :events_enabled, default: "false").and_return(true)

    expect(publisher.enabled?).to be_truthy
  end

  it "streams an Active Storage upload into the MedusaStorage draft root before sending" do
    uploaded = create(:datafile, dataset: dataset)
    key = File.join(uploaded.web_id, uploaded.binary_name)
    expect(draft_root).to receive(:copy_io_to).with(key, anything, nil, uploaded.binary.byte_size).ordered do |_key, io, _checksum, size|
      expect(io.read).to eq(File.binread(Rails.root.join("test/fixtures/files/analysis.csv")))
      expect(size).to eq(uploaded.binary.byte_size)
    end
    expect(exchange).to receive(:publish).ordered do |raw_payload, _options|
      expect(JSON.parse(raw_payload)["staging_key"]).to eq("uploads/#{key}")
    end

    expect(publisher.publish_datafile(uploaded, correlation_key: "corr-upload")).to be(true)
    expect(uploaded.reload).to have_attributes(storage_root: "draft", storage_key: key)
    expect(uploaded.binary).to be_attached
  end

  it "does not connect or publish when a binary is unavailable" do
    allow(draft_root).to receive(:exist?).and_return(false)

    expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(false)
    expect(Bunny).not_to have_received(:new)
    expect(exchange).not_to have_received(:publish)
    expect(logger).to have_received(:warn).with(/has no draft binary to ingest/)
  end

  it "does not publish or change location metadata when staging fails" do
    uploaded = create(:datafile, dataset: dataset)
    allow(draft_root).to receive(:copy_io_to).and_raise(IOError, "storage unavailable")

    expect(publisher.publish_datafile(uploaded, correlation_key: "corr-upload")).to be(false)
    expect(uploaded.reload.storage_root).to be_nil
    expect(Bunny).not_to have_received(:new)
    expect(logger).to have_received(:warn).with(
      "Ingest::RabbitmqEventPublisher failed: IOError: storage unavailable"
    )
  end

  it "does not publish an uncorrelatable request" do
    expect(publisher.publish_datafile(datafile, correlation_key: "")).to be(false)
    expect(Bunny).not_to have_received(:new)
    expect(logger).to have_received(:warn).with(/Ingest correlation key is missing/)
  end

  {
    events_enabled: "false",
    rabbitmq_url: " ",
    requests_queue: " "
  }.each do |key, value|
    it "does not connect when #{key} disables publishing" do
      default = key == :events_enabled ? "false" : ""
      allow(IdbConfig).to receive(:fetch).with(:ingest, key, default: default).and_return(value)

      expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(false)
      expect(Bunny).not_to have_received(:new)
      expect(exchange).not_to have_received(:publish)
    end
  end

  it "does not connect when Bunny is unavailable" do
    datafile
    fake_session = session
    hide_const("Bunny")

    expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(false)
    expect(fake_session).not_to have_received(:start)
  end

  it "reports an unconfirmed publish as a failure" do
    allow(channel).to receive(:wait_for_confirms).and_return(false)

    expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(false)
    expect(logger).to have_received(:warn).with(/not confirmed by RabbitMQ/)
    expect(session).to have_received(:close).once
  end

  it "logs publish failures and closes the connection" do
    allow(exchange).to receive(:publish).and_raise(IOError, "connection lost")

    expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(false)
    expect(logger).to have_received(:warn).with(
      "Ingest::RabbitmqEventPublisher failed: IOError: connection lost"
    )
    expect(session).to have_received(:close).once
  end

  it "does not close a session that failed to open" do
    allow(session).to receive(:start).and_raise(IOError, "cannot connect")
    allow(session).to receive(:open?).and_return(false)

    expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(false)
    expect(session).not_to have_received(:close)
    expect(exchange).not_to have_received(:publish)
  end

  it "logs connection construction failures" do
    allow(Bunny).to receive(:new).and_raise(ArgumentError, "invalid connection URL")

    expect(publisher.publish_datafile(datafile, correlation_key: "corr-123")).to be(false)
    expect(logger).to have_received(:warn).with(
      "Ingest::RabbitmqEventPublisher failed: ArgumentError: invalid connection URL"
    )
    expect(session).not_to have_received(:close)
  end
end
