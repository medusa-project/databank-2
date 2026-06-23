require "rails_helper"
require "rake"

RSpec.describe "archive_extractor tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:extract_pending_task) { Rake::Task["archive_extractor:extract_pending"] }
  let(:poll_responses_task) { Rake::Task["archive_extractor:poll_responses"] }

  before do
    extract_pending_task.reenable
    poll_responses_task.reenable
    ENV.delete("DRY_RUN")
    ENV.delete("MAX_BATCH")
    ENV.delete("BATCH_SIZE")
  end

  it "does not invoke ECS in dry run mode" do
    datafile = create(:datafile)
    ArchiveExtractRequest.create!(datafile: datafile, status: :pending)

    invoker = instance_double(ArchiveExtractor::FargateInvoker, current_task_count: 0)
    allow(invoker).to receive(:invoke_extraction)

    allow(ArchiveExtractor::Config).to receive(:enabled?).and_return(true)
    allow(ArchiveExtractor::Config).to receive(:use_mocks?).and_return(false)
    allow(ArchiveExtractor::Config).to receive(:max_batch_size).and_return(9)
    allow(ArchiveExtractor::Config).to receive(:max_task_capacity).and_return(49)
    allow(ArchiveExtractor::FargateInvoker).to receive(:new).and_return(invoker)

    ENV["DRY_RUN"] = "true"
    extract_pending_task.invoke

    expect(invoker).not_to have_received(:invoke_extraction)
  end

  it "passes batch size to response consumer task" do
    summary = ArchiveExtractor::ResponseConsumer::Summary.new(processed: 1, succeeded: 1, failed: 0, skipped: 0)
    consumer = instance_double(ArchiveExtractor::ResponseConsumer, poll_responses: summary)

    allow(ArchiveExtractor::Config).to receive(:enabled?).and_return(true)
    allow(ArchiveExtractor::Config).to receive(:use_mocks?).and_return(false)
    allow(ArchiveExtractor::ResponseConsumer).to receive(:new).and_return(consumer)

    ENV["BATCH_SIZE"] = "7"
    poll_responses_task.invoke

    expect(consumer).to have_received(:poll_responses).with(batch_size: 7)
  end
end
