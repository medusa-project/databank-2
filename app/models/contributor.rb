class Contributor < ApplicationRecord
  belongs_to :dataset

  before_validation :sync_name_fields

  validate :name_present
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :row_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  private

  def name_present
    has_legacy_name = institution_name.present? || (given_name.present? && family_name.present?)
    has_current_name = name.present?

    return if has_legacy_name || has_current_name

    errors.add(:base, "Contributor must have either an institution name, both a given name and family name, or a name")
  end

  def sync_name_fields
    if name.blank?
      synthesized = ""
      if institution_name.present?
        synthesized = institution_name
      else
        synthesized = [ given_name, family_name ].compact.join(" ").strip
      end
      self.name = synthesized if synthesized.present?
    end

    if row_position.present? && position.blank?
      self.position = row_position
    elsif position.present? && row_position.blank?
      self.row_position = position
    end
  end
end
