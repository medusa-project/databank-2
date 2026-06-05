require "rails_helper"

RSpec.describe Ingest::PublishDatasetEventJob, type: :job do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-7444444",
      title: "Job Event Dataset",
      description: "Event job test dataset",
      owner_uid: "owner-job",
      depositor_name: "Owner Job",
      depositor_email: "owner-job@example.edu",
      published_at: Time.current,
      publication_state: :published
    )
  end

  it "performs when publisher succeeds" do
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_dataset_published: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expected_key = "dataset.published:#{dataset.id}:#{dataset.published_at.utc.iso8601}"
    expect(publisher).to have_received(:publish_dataset_published).with(dataset, correlation_key: expected_key)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.dataset_id).to eq(dataset.id)
    expect(attempt.integration).to eq("ingest")
    expect(attempt.status).to eq("succeeded")
    expect(attempt.idempotency_key).to include("dataset.published:")
    expect(attempt.correlation_key).to eq(expected_key)
  end

  it "enqueues a retry when publisher returns false" do
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_dataset_published: false)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    clear_enqueued_jobs

    expect {
      described_class.perform_now(dataset.id)
    }.to change {
      enqueued_jobs.count { |job| job[:job] == described_class }
    }.by_at_least(1)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.integration).to eq("ingest")
    expect(attempt.status).to eq("failed")
  end

  it "does not republish when a succeeded attempt already exists" do
    key = "dataset.published:#{dataset.id}:#{dataset.published_at.utc.iso8601}"
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: key
    )

    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true)
    allow(publisher).to receive(:publish_dataset_published)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expect(publisher).not_to have_received(:publish_dataset_published)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.integration).to eq("ingest")
    expect(attempt.status).to eq("skipped")
    expect(attempt.details).to include("reason" => "already_succeeded")
  end

  it "uses provided replay idempotency key" do
    replay_key = "dataset.published:#{dataset.id}:manual-replay"
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: replay_key
    )

    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true)
    allow(publisher).to receive(:publish_dataset_published)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id, replay_key) }.not_to raise_error
    expect(publisher).not_to have_received(:publish_dataset_published)
  end

  it "records skipped attempt when publisher is disabled" do
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: false)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.integration).to eq("ingest")
    expect(attempt.status).to eq("skipped")
    expect(attempt.details).to include("reason" => "integration_disabled")
  end
end
