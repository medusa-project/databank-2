require "rails_helper"

RSpec.describe "Search reindex callbacks", type: :model do
  include ActiveJob::TestHelper

  let!(:dataset) do
    Dataset.create!(
      key: "IDB-7654321",
      title: "Land Surface Temperatures",
      description: "Daily observations",
      owner_uid: "owner2",
      depositor_name: "Owner Two",
      depositor_email: "owner2@example.edu"
    )
  end

  before do
    clear_enqueued_jobs
  end

  it "enqueues reindex when creator changes" do
    expect {
      Creator.create!(dataset: dataset, name: "Ada Lovelace", position: 1)
    }.to have_enqueued_job(Search::IndexDatasetJob).with(dataset.id)
  end

  it "enqueues reindex when contributor changes" do
    expect {
      Contributor.create!(dataset: dataset, name: "Grace Hopper", position: 1)
    }.to have_enqueued_job(Search::IndexDatasetJob).with(dataset.id)
  end

  it "enqueues reindex when funder changes" do
    expect {
      Funder.create!(dataset: dataset, name: "NSF", position: 1)
    }.to have_enqueued_job(Search::IndexDatasetJob).with(dataset.id)
  end

  it "enqueues reindex when related material changes" do
    expect {
      RelatedMaterial.create!(
        dataset: dataset,
        title: "Companion Article",
        uri: "https://example.org/article",
        position: 1
      )
    }.to have_enqueued_job(Search::IndexDatasetJob).with(dataset.id)
  end
end
