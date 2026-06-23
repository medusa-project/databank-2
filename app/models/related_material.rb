class RelatedMaterial < ApplicationRecord
  VERSION_PREVIOUS_RELATION = "IsPreviousVersionOf"
  VERSION_NEW_RELATION = "IsNewVersionOf"
  VERSION_RELATION_TYPES = [
    VERSION_PREVIOUS_RELATION,
    VERSION_NEW_RELATION
  ].freeze

  RELATION_TYPE_OPTIONS = [
    "IsSupplementTo",
    "IsSupplementedBy",
    "IsCitedBy",
    VERSION_PREVIOUS_RELATION,
    VERSION_NEW_RELATION
  ].freeze

  belongs_to :dataset
  audited associated_with: :dataset
  has_many :related_material_relationships, -> { order(:position, :id) }, dependent: :destroy

  before_validation :sync_legacy_fields
  after_save :sync_relationship_assertions

  validates :title, presence: true
  validates :uri, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true
  validates :relation_type, presence: true, if: :uri?
  validates :relation_type, inclusion: { in: RELATION_TYPE_OPTIONS }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :row_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def uri?
    uri.present?
  end

  def relation_types
    from_assertions = related_material_relationships.map(&:relation_type)
    return from_assertions if from_assertions.any?

    parsed_relationship_types
  end

  def version_relation?
    relation_types.any? { |value| VERSION_RELATION_TYPES.include?(value) }
  end

  private

  def sync_legacy_fields
    self.title = citation if title.blank? && citation.present?
    self.title = link if title.blank? && link.present?
    self.title = material_type if title.blank? && material_type.present?

    if row_position.present? && position.blank?
      self.position = row_position
    elsif position.present? && row_position.blank?
      self.row_position = position
    end

    normalized_relationships = parsed_relationship_types
    self.relation_type = normalized_relationships.first
    self.datacite_list = normalized_relationships.join(",") if normalized_relationships.any?
    self.datacite_list = nil if normalized_relationships.empty?
  end

  def parsed_relationship_types
    values = []
    values.concat(datacite_list.to_s.split(","))
    values << relation_type if relation_type.present?

    values
      .map { |value| value.to_s.strip }
      .reject(&:blank?)
      .select { |value| RELATION_TYPE_OPTIONS.include?(value) }
      .uniq
  end

  def sync_relationship_assertions
    desired = parsed_relationship_types
    existing = related_material_relationships.index_by(&:relation_type)

    desired.each_with_index do |relation, index|
      position = index + 1
      record = existing.delete(relation)

      if record
        record.update_columns(position: position, updated_at: Time.current) if record.position != position
      else
        related_material_relationships.create!(relation_type: relation, position: position)
      end
    end

    existing.each_value(&:destroy!)
  end
end
