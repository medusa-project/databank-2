class Funder < ApplicationRecord
  belongs_to :dataset

  audited associated_with: :dataset

  before_validation :sync_legacy_fields

  validates :name, presence: true
  validates :code, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :row_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  private

  def sync_legacy_fields
    self.code = FunderCatalog::OTHER_CODE if code.blank?

    self.award_number = grant if award_number.blank? && grant.present?
    self.grant = award_number if grant.blank? && award_number.present?

    if row_position.present? && position.blank?
      self.position = row_position
    elsif position.present? && row_position.blank?
      self.row_position = position
    end
  end
end
