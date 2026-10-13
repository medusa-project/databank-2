require "rails_helper"
require "rake"

RSpec.describe "medusa tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task) { Rake::Task["medusa:reconcile_all_medusa"] }

  before do
    task.reenable
    ENV.delete("DATASET_KEY")
  end

  it "sets all_medusa true when every datafile is in the medusa storage root" do
    dataset = Dataset.create!(
      key: "IDB-5555555",
      title: "Reconcile Dataset",
      description: "Dataset for medusa reconcile task",
      owner_uid: "owner-reconcile",
      depositor_name: "Owner Reconcile",
      depositor_email: "owner-reconcile@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE
    )
    dataset.datafiles.create!(web_id: "abcde", binary_name: "a.csv", storage_root: "medusa", storage_key: "k1")

    task.invoke

    expect(dataset.reload.all_medusa).to be true
  end

  it "clears all_medusa when a datafile is no longer in the medusa storage root" do
    dataset = Dataset.create!(
      key: "IDB-6666666",
      title: "Reconcile Drift Dataset",
      description: "Dataset for medusa reconcile drift",
      owner_uid: "owner-reconcile-drift",
      depositor_name: "Owner Reconcile Drift",
      depositor_email: "owner-reconcile-drift@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE,
      all_medusa: true
    )
    dataset.datafiles.create!(web_id: "fghij", binary_name: "b.csv", storage_root: "draft", storage_key: "k2")

    task.invoke

    expect(dataset.reload.all_medusa).to be false
  end

  it "scopes to a single dataset when DATASET_KEY is set" do
    other = Dataset.create!(
      key: "IDB-7777777",
      title: "Other Dataset",
      description: "Should not be touched",
      owner_uid: "owner-other",
      depositor_name: "Owner Other",
      depositor_email: "owner-other@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE
    )
    other.datafiles.create!(web_id: "klmno", binary_name: "c.csv", storage_root: "medusa", storage_key: "k3")

    ENV["DATASET_KEY"] = "IDB-does-not-match"
    task.invoke

    expect(other.reload.all_medusa).to be false
  end
end
