require "rails_helper"

RSpec.describe DatasetVersionGroup, type: :model do
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

  it "selects the highest reachable published version as latest_published_version" do
    source = create_dataset(
      title: "Source",
      key: "IDB-9200001",
      identifier: "10.5555/IDB-9200001",
      publication_state: :published
    )

    draft_successor = create_dataset(title: "Draft Successor", publication_state: :draft)
    source.related_materials.create!(
      title: draft_successor.title,
      uri: "https://example.test/datasets/#{draft_successor.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    newest_published = create_dataset(
      title: "Newest Published",
      key: "IDB-9200002",
      identifier: "10.5555/IDB-9200002",
      publication_state: :published
    )
    draft_successor.related_materials.create!(
      title: newest_published.title,
      uri: "https://example.test/datasets/#{newest_published.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    group = described_class.new(source)

    expect(group.latest_published_version).to eq(newest_published)
    expect(group.entries.map { |entry| entry[:dataset] }).to include(source, draft_successor, newest_published)
  end
end
