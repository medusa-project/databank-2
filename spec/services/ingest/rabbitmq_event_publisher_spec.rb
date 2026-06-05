require "rails_helper"

RSpec.describe Ingest::RabbitmqEventPublisher, type: :service do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-7333333",
      title: "Ingest Target Dataset",
      description: "Published dataset event test",
      owner_uid: "owner-ingest",
      depositor_name: "Owner Ingest",
      depositor_email: "owner-ingest@example.edu",
      publication_state: :published,
      published_at: Time.current,
      identifier: "10.5555/IDB-7333333"
    )
  end

  before do
    ingest_config = {
      events_enabled: "true",
      rabbitmq_url: "amqp://guest:guest@localhost:5672",
      events_exchange: "databank.ingest",
      events_routing_key: "dataset.published"
    }

    allow(IdbConfig).to receive(:fetch) do |*keys, default: nil|
      value = keys.reduce({ ingest: ingest_config }) do |memo, key|
        break nil unless memo.respond_to?(:[])

        memo[key.to_sym] || memo[key.to_s]
      end

      value.nil? ? default : value
    end
  end

  it "publishes dataset.published event to configured exchange" do
    fake_exchange = instance_double("Bunny::Exchange")
    fake_channel = instance_double("Bunny::Channel")
    fake_session = instance_double("Bunny::Session", create_channel: fake_channel, open?: true)

    allow(fake_channel).to receive(:topic).with("databank.ingest", durable: true).and_return(fake_exchange)
    allow(fake_exchange).to receive(:publish)
    allow(fake_session).to receive(:start)
    allow(fake_session).to receive(:close)

    bunny_class = Class.new do
      def self.new(_url); end
    end
    stub_const("Bunny", bunny_class)
    allow(Bunny).to receive(:new).and_return(fake_session)

    result = described_class.new.publish_dataset_published(dataset, correlation_key: "corr-123")

    expect(result).to eq(true)
    expect(fake_exchange).to have_received(:publish).with(
      include('"event":"dataset.published"', '"key":"IDB-7333333"', '"correlation_key":"corr-123"'),
      hash_including(
        routing_key: "dataset.published",
        content_type: "application/json",
        persistent: true
      )
    )
    expect(fake_session).to have_received(:close)
  end

  it "returns false when required config is missing" do
    allow(IdbConfig).to receive(:fetch).with(:ingest, :rabbitmq_url, default: "").and_return("")

    expect(described_class.new.publish_dataset_published(dataset)).to eq(false)
  end
end
