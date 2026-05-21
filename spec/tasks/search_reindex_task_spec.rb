require "rails_helper"
require "rake"

RSpec.describe "search:reindex_all" do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task) { Rake::Task["search:reindex_all"] }

  before do
    task.reenable
  end

  it "enqueues index job for every dataset" do
    dataset_one = Dataset.create!(
      key: "IDB-9000001",
      title: "Dataset One",
      description: "One",
      owner_uid: "owner-a",
      depositor_name: "Owner A",
      depositor_email: "owner-a@example.edu"
    )

    dataset_two = Dataset.create!(
      key: "IDB-9000002",
      title: "Dataset Two",
      description: "Two",
      owner_uid: "owner-b",
      depositor_name: "Owner B",
      depositor_email: "owner-b@example.edu"
    )

    task.invoke

    jobs = enqueued_jobs.select { |job| job[:job] == Search::IndexDatasetJob }
    args = jobs.map { |job| job[:args].first }

    expect(args).to include(dataset_one.id)
    expect(args).to include(dataset_two.id)
  end
end
