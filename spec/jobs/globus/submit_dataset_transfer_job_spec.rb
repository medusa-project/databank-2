require "rails_helper"

RSpec.describe Globus::SubmitDatasetTransferJob, type: :job do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-4666666",
      title: "Globus Job Dataset",
      description: "Job-level transfer test",
      owner_uid: "owner-globus-job",
      depositor_name: "Owner Globus Job",
      depositor_email: "owner-globus-job@example.edu",
      published_at: Time.current,
      publication_state: :published
    )
  end

  it "performs when service is enabled and succeeds" do
    service = instance_double(Globus::TransferService, enabled?: true, submit_dataset_transfer: true)
    allow(Globus::TransferService).to receive(:new).and_return(service)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expect(service).to have_received(:submit_dataset_transfer).with(dataset)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.dataset_id).to eq(dataset.id)
    expect(attempt.integration).to eq("globus")
    expect(attempt.status).to eq("succeeded")
    expect(attempt.idempotency_key).to include("dataset.published:")
  end

  it "records skipped attempt when service is disabled" do
    service = instance_double(Globus::TransferService, enabled?: false)
    allow(service).to receive(:submit_dataset_transfer)
    allow(Globus::TransferService).to receive(:new).and_return(service)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expect(service).not_to have_received(:submit_dataset_transfer)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.integration).to eq("globus")
    expect(attempt.status).to eq("skipped")
    expect(attempt.details).to include("reason" => "integration_disabled")
  end

  it "enqueues retry when service returns false" do
    service = instance_double(Globus::TransferService, enabled?: true, submit_dataset_transfer: false)
    allow(Globus::TransferService).to receive(:new).and_return(service)

    clear_enqueued_jobs

    expect {
      described_class.perform_now(dataset.id)
    }.to change {
      enqueued_jobs.count { |job| job[:job] == described_class }
    }.by_at_least(1)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.integration).to eq("globus")
    expect(attempt.status).to eq("failed")
  end

  it "does not resubmit transfer when a succeeded attempt already exists" do
    key = "dataset.published:#{dataset.id}:#{dataset.published_at.utc.iso8601}"
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :globus,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: key
    )

    service = instance_double(Globus::TransferService, enabled?: true)
    allow(service).to receive(:submit_dataset_transfer)
    allow(Globus::TransferService).to receive(:new).and_return(service)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expect(service).not_to have_received(:submit_dataset_transfer)

    attempt = ExternalDeliveryAttempt.order(:created_at).last
    expect(attempt.integration).to eq("globus")
    expect(attempt.status).to eq("skipped")
    expect(attempt.details).to include("reason" => "already_succeeded")
  end
end
