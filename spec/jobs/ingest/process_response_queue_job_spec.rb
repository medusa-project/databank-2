require "rails_helper"

RSpec.describe Ingest::ProcessResponseQueueJob, type: :job do
  it "consumes a response batch when consumer is enabled" do
    consumer = instance_double(
      Ingest::RabbitmqResponseConsumer,
      enabled?: true,
      consume_batch: Ingest::RabbitmqResponseConsumer::Result.new(processed: 2, matched: 1, unmatched: 1, invalid: 0)
    )

    allow(Ingest::RabbitmqResponseConsumer).to receive(:new).and_return(consumer)

    described_class.perform_now(25)

    expect(consumer).to have_received(:consume_batch).with(max_messages: 25)
  end

  it "skips processing when consumer is disabled" do
    consumer = instance_double(Ingest::RabbitmqResponseConsumer, enabled?: false)
    allow(consumer).to receive(:consume_batch)
    allow(Ingest::RabbitmqResponseConsumer).to receive(:new).and_return(consumer)

    described_class.perform_now

    expect(consumer).not_to have_received(:consume_batch)
  end
end
