require "rails_helper"

RSpec.describe Dataset::Globusable, type: :model do
  let(:dataset) do
    Dataset.create!(
      title: "Globusable Dataset",
      description: "Dataset for globusable behavior",
      owner_uid: "owner-globusable",
      depositor_name: "Owner Globusable",
      depositor_email: "owner-globusable@example.edu",
      publication_state: :published,
      published_at: Time.current,
      embargo: Dataset::EMBARGO_NONE
    )
  end

  describe "#globus_downloadable?" do
    it "is false when the dataset is not published" do
      dataset.update!(publication_state: :draft, all_globus: true)

      expect(dataset.globus_downloadable?).to be false
    end

    it "is false when all_globus has not been set" do
      expect(dataset.globus_downloadable?).to be false
    end

    it "is true when the dataset is published and all_globus is true" do
      dataset.update!(all_globus: true)

      expect(dataset.globus_downloadable?).to be true
    end
  end
end
