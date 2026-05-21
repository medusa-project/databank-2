require "rails_helper"

RSpec.describe Ingest::PublishDatasetEventJob, type: :job do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-7444444",
      title: "Job Event Dataset",
      description: "Event job test dataset",
      owner_uid: "owner-job",
      depositor_name: "Owner Job",
      depositor_email: "owner-job@example.edu"
    )
  end

  it "performs when publisher succeeds" do
    publisher = instance_double(Ingest::RabbitmqEventPublisher, publish_dataset_published: true)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expect(publisher).to have_received(:publish_dataset_published).with(dataset)
  end

  it "enqueues a retry when publisher returns false" do
    publisher = instance_double(Ingest::RabbitmqEventPublisher, publish_dataset_published: false)
    allow(Ingest::RabbitmqEventPublisher).to receive(:new).and_return(publisher)

    clear_enqueued_jobs

    expect {
      described_class.perform_now(dataset.id)
    }.to change {
      enqueued_jobs.count { |job| job[:job] == described_class }
    }.by_at_least(1)
  end
end
