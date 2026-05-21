require "rails_helper"

RSpec.describe Search::DeleteDatasetJob, type: :job do
  it "performs when indexer delete succeeds" do
    fake_indexer = instance_double(Search::SolrIndexer, delete_dataset: true)
    allow(Search::SolrIndexer).to receive(:new).and_return(fake_indexer)

    expect { described_class.perform_now("IDB-8123456") }.not_to raise_error
    expect(fake_indexer).to have_received(:delete_dataset).with("IDB-8123456")
  end

  it "does nothing for blank key" do
    fake_indexer = instance_double(Search::SolrIndexer)
    allow(fake_indexer).to receive(:delete_dataset).and_return(true)
    allow(Search::SolrIndexer).to receive(:new).and_return(fake_indexer)

    expect { described_class.perform_now(nil) }.not_to raise_error
    expect(fake_indexer).not_to have_received(:delete_dataset)
  end

  it "enqueues a retry when indexer delete returns false" do
    fake_indexer = instance_double(Search::SolrIndexer, delete_dataset: false)
    allow(Search::SolrIndexer).to receive(:new).and_return(fake_indexer)

    expect {
      described_class.perform_now("IDB-8999999")
    }.to change {
      enqueued_jobs.count { |job| job[:job] == described_class }
    }.by(1)
  end
end
