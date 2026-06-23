class DatasetVersionBuilder
  def initialize(previous_dataset:, new_version_uri_builder:)
    @previous_dataset = previous_dataset
    @new_version_uri_builder = new_version_uri_builder
  end

  def call
    raise ArgumentError, "previous dataset must be published" unless @previous_dataset.published?

    Dataset.transaction do
      new_dataset = Dataset.create!(
        title: @previous_dataset.title,
        description: @previous_dataset.description,
        keywords: @previous_dataset.keywords,
        subject: @previous_dataset.subject,
        license: @previous_dataset.license,
        publisher: @previous_dataset.publisher,
        owner_uid: @previous_dataset.owner_uid,
        depositor_name: @previous_dataset.depositor_name,
        depositor_email: @previous_dataset.depositor_email,
        embargo: Dataset::EMBARGO_NONE,
        release_date: nil,
        publication_state: :draft
      )

      copy_creators_to(new_dataset)
      copy_contributors_to(new_dataset)
      copy_funders_to(new_dataset)
      copy_related_materials_to(new_dataset)
      add_version_relationships_for(new_dataset)

      new_dataset
    end
  end

  private

  def copy_creators_to(new_dataset)
    @previous_dataset.creators.each do |creator|
      new_dataset.creators.create!(
        name: creator.name,
        email: creator.email,
        contact: creator.contact,
        position: creator.position
      )
    end
  end

  def copy_contributors_to(new_dataset)
    @previous_dataset.contributors.each do |contributor|
      new_dataset.contributors.create!(
        name: contributor.name,
        email: contributor.email,
        role: contributor.role,
        position: contributor.position
      )
    end
  end

  def copy_funders_to(new_dataset)
    @previous_dataset.funders.each do |funder|
      new_dataset.funders.create!(
        name: funder.name,
        identifier: funder.identifier,
        award_number: funder.award_number,
        position: funder.position
      )
    end
  end

  def copy_related_materials_to(new_dataset)
    @previous_dataset.nonversion_related_materials.each do |material|
      relation_values = material.relation_types
      new_dataset.related_materials.create!(
        title: material.title,
        uri: material.uri,
        relation_type: relation_values.first,
        datacite_list: relation_values.join(","),
        position: material.position
      )
    end
  end

  def add_version_relationships_for(new_dataset)
    new_dataset.related_materials.create!(
      title: @previous_dataset.title,
      uri: @previous_dataset.persistent_url,
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      position: next_position(new_dataset.related_materials)
    )

    @previous_dataset.related_materials.create!(
      title: new_dataset.title,
      uri: @new_version_uri_builder.call(new_dataset),
      relation_type: RelatedMaterial::VERSION_NEW_RELATION,
      position: next_position(@previous_dataset.related_materials)
    )
  end

  def next_position(scope)
    scope.maximum(:position).to_i + 1
  end
end
