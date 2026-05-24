require "rails_helper"

RSpec.describe DatasetVersionBuilder do
  describe "#call" do
    it "copies metadata and adds version lineage links" do
      previous = Dataset.create!(
        title: "Published Source",
        description: "v1 dataset",
        keywords: "climate,temperature",
        subject: "Earth Systems",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner User",
        depositor_email: "owner@example.edu",
        publication_state: :published,
        identifier: "10.5555/IDB-1112223"
      )

      previous.creators.create!(name: "Creator One", email: "creator@example.edu", contact: true, position: 1)
      previous.contributors.create!(name: "Contributor One", email: "contrib@example.edu", role: "Data Curator", position: 1)
      previous.funders.create!(name: "DOE", identifier: "10.13039/100000015", award_number: "DE-123", position: 1)
      previous.related_materials.create!(title: "Paper", uri: "https://example.org/paper", relation_type: "IsSupplementTo", position: 1)
      previous.related_materials.create!(title: "Older Version", uri: "https://example.org/older", relation_type: RelatedMaterial::VERSION_NEW_RELATION, position: 2)

      service = described_class.new(
        previous_dataset: previous,
        new_version_uri_builder: ->(dataset) { "https://example.test/datasets/#{dataset.key}" }
      )

      new_dataset = nil
      expect {
        new_dataset = service.call
      }.to change(Dataset, :count).by(1)

      expect(new_dataset).to be_persisted
      expect(new_dataset).to be_draft
      expect(new_dataset.identifier).to be_nil
      expect(new_dataset.title).to eq(previous.title)
      expect(new_dataset.description).to eq(previous.description)
      expect(new_dataset.keywords).to eq(previous.keywords)
      expect(new_dataset.subject).to eq(previous.subject)
      expect(new_dataset.license).to eq(previous.license)
      expect(new_dataset.publisher).to eq(previous.publisher)
      expect(new_dataset.depositor_email).to eq(previous.depositor_email)

      expect(new_dataset.creators.pluck(:name, :email, :contact)).to eq([ [ "Creator One", "creator@example.edu", true ] ])
      expect(new_dataset.contributors.pluck(:name, :email, :role)).to eq([ [ "Contributor One", "contrib@example.edu", "Data Curator" ] ])
      expect(new_dataset.funders.pluck(:name, :identifier, :award_number)).to eq([ [ "DOE", "10.13039/100000015", "DE-123" ] ])

      expect(new_dataset.related_materials.where(relation_type: "IsSupplementTo").pluck(:title, :uri)).to eq([ [ "Paper", "https://example.org/paper" ] ])
      expect(new_dataset.related_materials.where(relation_type: RelatedMaterial::VERSION_NEW_RELATION)).to be_empty

      previous_link = new_dataset.related_materials.find_by!(relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION)
      expect(previous_link.uri).to eq("https://doi.org/10.5555/IDB-1112223")

      successor_link = previous.related_materials.where(relation_type: RelatedMaterial::VERSION_NEW_RELATION).reorder(created_at: :desc).first
      expect(successor_link.uri).to eq("https://example.test/datasets/#{new_dataset.key}")
    end

    it "raises when source dataset is not published" do
      previous = Dataset.create!(
        title: "Draft Source",
        description: "draft",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner User",
        depositor_email: "owner@example.edu",
        publication_state: :draft
      )

      service = described_class.new(
        previous_dataset: previous,
        new_version_uri_builder: ->(dataset) { "https://example.test/datasets/#{dataset.key}" }
      )

      expect {
        service.call
      }.to raise_error(ArgumentError, "previous dataset must be published")
    end

    it "rolls back all writes when a copy step fails" do
      previous = Dataset.create!(
        title: "Published Source",
        description: "v1 dataset",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner User",
        depositor_email: "owner@example.edu",
        publication_state: :published,
        identifier: "10.5555/IDB-4445556"
      )
      previous.creators.create!(name: "Creator One", email: "creator@example.edu", contact: true, position: 1)

      initial_dataset_count = Dataset.count
      initial_related_count = previous.related_materials.count

      service = described_class.new(
        previous_dataset: previous,
        new_version_uri_builder: ->(dataset) { "https://example.test/datasets/#{dataset.key}" }
      )
      allow(service).to receive(:add_version_relationships_for).and_raise(StandardError, "forced failure")

      expect {
        service.call
      }.to raise_error(StandardError, "forced failure")

      expect(Dataset.count).to eq(initial_dataset_count)
      expect(previous.reload.related_materials.count).to eq(initial_related_count)
    end
  end
end
