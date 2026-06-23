require "rails_helper"

RSpec.describe ArchiveExtractResponseJob, type: :job do
  it "uses mock response consumer when mocks are enabled" do
    summary = ArchiveExtractor::MockResponseConsumer::Summary.new(processed: 1, succeeded: 1, failed: 0, skipped: 0)
    consumer = instance_double(ArchiveExtractor::MockResponseConsumer, poll_responses: summary)

    allow(ArchiveExtractor::Config).to receive(:use_mocks?).and_return(true)
    allow(ArchiveExtractor::MockResponseConsumer).to receive(:new).and_return(consumer)

    described_class.perform_now(batch_size: 3)

    expect(consumer).to have_received(:poll_responses).with(batch_size: 3)
  end

  it "uses real response consumer when mocks are disabled" do
    summary = ArchiveExtractor::ResponseConsumer::Summary.new(processed: 0, succeeded: 0, failed: 0, skipped: 0)
    consumer = instance_double(ArchiveExtractor::ResponseConsumer, poll_responses: summary)

    allow(ArchiveExtractor::Config).to receive(:use_mocks?).and_return(false)
    allow(ArchiveExtractor::ResponseConsumer).to receive(:new).and_return(consumer)

    described_class.perform_now(batch_size: 2)

    expect(consumer).to have_received(:poll_responses).with(batch_size: 2)
  end
end
