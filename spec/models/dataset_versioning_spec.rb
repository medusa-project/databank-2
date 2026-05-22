require "rails_helper"

RSpec.describe Dataset, type: :model do
  describe "version lineage helpers" do
    def create_dataset(attrs = {})
      Dataset.create!({
        title: "Dataset",
        description: "desc",
        keywords: "k",
        subject: "s",
        license: "CC0",
        publisher: "Illinois Data Bank",
        owner_uid: "owner-uid",
        depositor_name: "Owner",
        depositor_email: "owner@example.edu",
        publication_state: :draft
      }.merge(attrs))
    end

    it "resolves previous version dataset from DOI URL" do
      previous = create_dataset(publication_state: :published, identifier: "10.5555/IDB-6000001", key: "IDB-6000001", title: "Previous")
      current = create_dataset(title: "Current")
      current.related_materials.create!(
        title: previous.title,
        uri: "https://doi.org/10.5555/IDB-6000001",
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )

      expect(current.previous_version_dataset).to eq(previous)
    end

    it "resolves previous version dataset from internal dataset URL" do
      previous = create_dataset(publication_state: :published, identifier: "10.5555/IDB-6000002", key: "IDB-6000002", title: "Previous")
      current = create_dataset(title: "Current")
      current.related_materials.create!(
        title: previous.title,
        uri: "http://127.0.0.1:3000/datasets/#{previous.key}",
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )

      expect(current.previous_version_dataset).to eq(previous)
    end

    it "finds successor from reciprocal previous-version relation" do
      current = create_dataset(publication_state: :published, identifier: "10.5555/IDB-6000003", key: "IDB-6000003", title: "Current")
      successor = create_dataset(title: "Successor", publication_state: :published)
      successor.related_materials.create!(
        title: current.title,
        uri: current.persistent_url,
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )

      expect(current.version_successor).to eq(successor)
      expect(current.version_eligible?).to be(false)
    end

    it "falls back to successor URI relation when reciprocal relation is absent" do
      current = create_dataset(publication_state: :published, identifier: "10.5555/IDB-6000004", key: "IDB-6000004", title: "Current")
      successor = create_dataset(title: "Successor", publication_state: :published)
      current.related_materials.create!(
        title: successor.title,
        uri: "https://example.test/datasets/#{successor.key}",
        relation_type: RelatedMaterial::VERSION_NEW_RELATION,
        position: 1
      )

      expect(current.version_successor).to eq(successor)
      expect(current.version_eligible?).to be(false)
    end

    it "does not treat a draft successor as a newer published version" do
      current = create_dataset(publication_state: :published, identifier: "10.5555/IDB-6000005", key: "IDB-6000005", title: "Current")
      draft_successor = create_dataset(title: "Draft Successor", publication_state: :draft)
      draft_successor.related_materials.create!(
        title: current.title,
        uri: current.persistent_url,
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )

      expect(current.version_successor).to be_nil
      expect(current.has_newer_published_version?).to be(false)
      expect(current.version_eligible?).to be(true)
    end
  end
end
