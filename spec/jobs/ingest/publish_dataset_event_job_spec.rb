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

  let!(:datafile) { create(:datafile, dataset: dataset) }

  it "performs when publisher succeeds" do
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expected_key = "dataset.published:#{dataset.id}:#{dataset.published_at.utc.iso8601}:datafile:#{datafile.id}"
    expect(publisher).to have_received(:publish_datafile).with(datafile, correlation_key: expected_key)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.dataset_id).to eq(dataset.id)
    expect(attempt.integration).to eq("ingest")
    expect(attempt.status).to eq("succeeded")
    expect(attempt.idempotency_key).to include("dataset.published:")
    expect(attempt.correlation_key).to eq(expected_key)
    expect(attempt.details).to include("datafile_id" => datafile.id)
  end

  it "enqueues a retry when publisher returns false" do
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: false)
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
    key = "dataset.published:#{dataset.id}:#{dataset.published_at.utc.iso8601}:datafile:#{datafile.id}"
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: key
    )

    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true)
    allow(publisher).to receive(:publish_datafile)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expect(publisher).not_to have_received(:publish_datafile)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.integration).to eq("ingest")
    expect(attempt.status).to eq("succeeded")
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
    allow(publisher).to receive(:publish_datafile)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id, replay_key, datafile.id) }.not_to raise_error
    expect(publisher).not_to have_received(:publish_datafile)
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

  it "records distinct attempts and correlation keys for every file" do
    second = create(:datafile, dataset: dataset, attach_binary: false, binary_name: "second.csv")
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.to change(ExternalDeliveryAttempt, :count).by(2)
    attempts = ExternalDeliveryAttempt.order(:id).last(2)
    expect(attempts.map { |entry| entry.details["datafile_id"] }).to eq([ datafile.id, second.id ])
    expect(attempts.map(&:correlation_key).uniq.size).to eq(2)
    attempts.each do |entry|
      expect(publisher).to have_received(:publish_datafile).with(
        dataset.datafiles.find(entry.details["datafile_id"]), correlation_key: entry.correlation_key
      )
    end
  end

  it "does not resend confirmed files when a later file fails and the job retries" do
    second = create(:datafile, dataset: dataset, attach_binary: false, binary_name: "second.csv")
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)
    allow(publisher).to receive(:publish_datafile).with(datafile, correlation_key: anything).and_return(true)
    allow(publisher).to receive(:publish_datafile).with(second, correlation_key: anything).and_return(false, true)

    described_class.perform_now(dataset.id)
    described_class.perform_now(dataset.id)

    expect(publisher).to have_received(:publish_datafile).with(datafile, correlation_key: anything).once
    expect(publisher).to have_received(:publish_datafile).with(second, correlation_key: anything).twice
  end

  it "replays only the specified file with its original idempotency key" do
    create(:datafile, dataset: dataset, attach_binary: false, binary_name: "second.csv")
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    described_class.perform_now(dataset.id, "file-replay-key", datafile.id)

    expect(publisher).to have_received(:publish_datafile).with(datafile, correlation_key: "file-replay-key").once
    expect(ExternalDeliveryAttempt.last.idempotency_key).to eq("file-replay-key")
  end

  it "does not send files already stored in Medusa" do
    datafile.update!(storage_root: "medusa")
    other = create(:datafile, dataset: dataset, attach_binary: false, binary_name: "second.csv")
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    described_class.perform_now(dataset.id)

    expect(publisher).to have_received(:publish_datafile).with(other, correlation_key: anything).once
    expect(publisher).not_to have_received(:publish_datafile).with(datafile, correlation_key: anything)
  end

  it "does not treat a legacy dataset notification as a confirmed file-ingest request" do
    key = "dataset.published:#{dataset.id}:#{dataset.published_at.utc.iso8601}"
    ExternalDeliveryAttempt.create!(
      dataset: dataset, integration: :ingest, event_name: "dataset.published",
      status: :succeeded, attempt: 1, idempotency_key: key
    )
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    described_class.perform_now(dataset.id)

    expect(publisher).to have_received(:publish_datafile).with(datafile, correlation_key: "#{key}:datafile:#{datafile.id}")
  end

  it "skips a dataset whose files are all already in Medusa" do
    datafile.update!(storage_root: "medusa")
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    described_class.perform_now(dataset.id)

    expect(publisher).not_to have_received(:publish_datafile)
    expect(ExternalDeliveryAttempt.last.details).to include("reason" => "no_files_to_ingest")
  end

  it "does not publish files with colliding preservation targets" do
    create(:datafile, dataset: dataset)
    publisher = instance_double(Ingest::RabbitmqEventPublisher, enabled?: true, publish_datafile: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.to have_enqueued_job(described_class)
    expect(publisher).not_to have_received(:publish_datafile)
  end
end
