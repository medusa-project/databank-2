require "rails_helper"
require "rake"

RSpec.describe "databank tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:cache_clear_task) { Rake::Task["databank:rails_cache:clear"] }

  before do
    cache_clear_task.reenable
  end

  it "clears Rails cache" do
    allow(Rails.cache).to receive(:clear)

    cache_clear_task.invoke

    expect(Rails.cache).to have_received(:clear)
  end
end
