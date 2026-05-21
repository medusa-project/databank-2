class Creator < ApplicationRecord
  belongs_to :dataset

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  after_save :ensure_exclusive_contact, if: :contact?

  private

  def ensure_exclusive_contact
    dataset.creators.where.not(id: id).where(contact: true).update_all(contact: false, updated_at: Time.current)
  end
end
