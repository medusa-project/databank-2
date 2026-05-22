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

  before_validation :sync_legacy_fields

  validates :title, presence: true
  validates :uri, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true
  validates :relation_type, presence: true, if: :uri?
  validates :relation_type, inclusion: { in: RELATION_TYPE_OPTIONS }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :row_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def uri?
    uri.present?
  end

  def version_relation?
    VERSION_RELATION_TYPES.include?(relation_type)
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
  end
end
