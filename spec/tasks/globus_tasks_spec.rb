require "rails_helper"
require "rake"

RSpec.describe "globus tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_task) { Rake::Task["globus:import_datafiles_from_ingest"] }
  let(:copy_task) { Rake::Task["globus:copy_public_datafiles"] }

  before do
    import_task.reenable
    copy_task.reenable
    ENV.delete("DATASET_KEY")
    ENV.delete("DRY_RUN")
    ENV.delete("DATASET_LIMIT")
  end

  it "passes env options to globus ingest import service" do
    ENV["DATASET_KEY"] = "IDB-1234567"
    ENV["DRY_RUN"] = "true"
    ENV["DATASET_LIMIT"] = "5"

    service = instance_double(Globus::IngestImportService, call: { created: 0, records: [] })
    expect(Globus::IngestImportService).to receive(:new).with(
      dataset_key: "IDB-1234567",
      dry_run: true,
      dataset_limit: 5
    ).and_return(service)

    import_task.invoke
  end

  it "passes env options to globus public copy service" do
    ENV["DRY_RUN"] = "1"

    service = instance_double(Globus::PublicCopyService, call: { copied: 0, records: [] })
    expect(Globus::PublicCopyService).to receive(:new).with(
      dataset_key: nil,
      dry_run: true,
      dataset_limit: 0
    ).and_return(service)

    copy_task.invoke
  end
end
