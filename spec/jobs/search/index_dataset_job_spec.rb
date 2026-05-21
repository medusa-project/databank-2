require "rails_helper"

RSpec.describe Search::IndexDatasetJob, type: :job do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-8111111",
      title: "Sea Ice",
      description: "Seasonal extent",
      owner_uid: "owner-index",
      depositor_name: "Owner Index",
      depositor_email: "owner-index@example.edu"
    )
  end

  it "performs when indexer succeeds" do
    fake_indexer = instance_double(Search::SolrIndexer, index_dataset: true)
    allow(Search::SolrIndexer).to receive(:new).and_return(fake_indexer)

    expect { described_class.perform_now(dataset.id) }.not_to raise_error
    expect(fake_indexer).to have_received(:index_dataset).with(dataset)
  end

  it "enqueues a retry when indexer returns false" do
    fake_indexer = instance_double(Search::SolrIndexer, index_dataset: false)
    allow(Search::SolrIndexer).to receive(:new).and_return(fake_indexer)

    clear_enqueued_jobs

    expect {
      described_class.perform_now(dataset.id)
    }.to change {
      enqueued_jobs.count { |job| job[:job] == described_class }
    }.by_at_least(1)
  end
end
