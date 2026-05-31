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

  it "stops traversing when a version chain loops back to an earlier dataset" do
    source = create_dataset(
      title: "Loop Source",
      key: "IDB-9200003",
      identifier: "10.5555/IDB-9200003",
      publication_state: :published
    )

    loop_successor = create_dataset(title: "Loop Successor", publication_state: :draft)

    source.related_materials.create!(
      title: loop_successor.title,
      uri: "https://example.test/datasets/#{loop_successor.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )
    loop_successor.related_materials.create!(
      title: source.title,
      uri: source.persistent_url,
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 1
    )

    group = described_class.new(source)

    expect(group.entries.map { |entry| entry[:dataset] }).to eq([ source, loop_successor ])
    expect(group.latest_published_version).to eq(source)
  end

  it "caps version chain traversal at the configured maximum length" do
    source = create_dataset(
      title: "Cap Source",
      key: "IDB-9200004",
      identifier: "10.5555/IDB-9200004",
      publication_state: :published
    )

    chain = [ source ]
    51.times do |index|
      chain << create_dataset(title: "Cap Successor #{index + 1}", publication_state: :draft)
    end

    chain.each_cons(2).with_index do |(current, successor), index|
      current.related_materials.create!(
        title: successor.title,
        uri: "https://example.test/datasets/#{successor.key}",
        relation_type: RelatedMaterial::VERSION_NEW_RELATION,
        position: index + 1
      )
      successor.related_materials.create!(
        title: current.title,
        uri: current.persistent_url,
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )
    end

    group = described_class.new(source)

    expect(group.entries.size).to eq(51)
    expect(group.entries.last[:dataset]).to eq(chain[50])
    expect(group.entries.map { |entry| entry[:dataset] }).not_to include(chain[51])
  end

  it "caps reverse version chain traversal at the configured maximum length" do
    source = create_dataset(
      title: "Reverse Cap Source",
      key: "IDB-9200005",
      identifier: "10.5555/IDB-9200005",
      publication_state: :draft
    )

    chain = [ source ]
    51.times do |index|
      chain << create_dataset(title: "Reverse Cap Previous #{index + 1}", publication_state: :draft)
    end

    chain.each_cons(2).with_index do |(previous, current), index|
      current.related_materials.create!(
        title: previous.title,
        uri: previous.persistent_url.presence || "https://example.test/datasets/#{previous.key}",
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        position: 1
      )
      previous.related_materials.create!(
        title: current.title,
        uri: "https://example.test/datasets/#{current.key}",
        relation_type: RelatedMaterial::VERSION_NEW_RELATION,
        position: index + 1
      )
    end

    group = described_class.new(chain.last)

    expect(group.entries.size).to eq(51)
    expect(group.entries.first[:dataset]).to eq(chain[1])
    expect(group.entries.map { |entry| entry[:dataset] }).not_to include(chain[0])
  end

  it "prefers the forward published version when the grouped dataset is a draft between published versions" do
    previous = create_dataset(
      title: "Previous Published",
      key: "IDB-9200006",
      identifier: "10.5555/IDB-9200006",
      publication_state: :published
    )
    current = create_dataset(
      title: "Current Draft",
      key: "IDB-9200007",
      publication_state: :draft
    )
    successor = create_dataset(
      title: "Successor Published",
      key: "IDB-9200008",
      identifier: "10.5555/IDB-9200008",
      publication_state: :published
    )

    current.related_materials.create!(
      title: previous.title,
      uri: previous.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: 1
    )
    current.related_materials.create!(
      title: successor.title,
      uri: "https://example.test/datasets/#{successor.key}",
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: 2
    )

    group = described_class.new(current)

    expect(group.entries.map { |entry| entry[:dataset] }).to eq([ previous, current, successor ])
    expect(group.latest_published_version).to eq(successor)
  end
end
