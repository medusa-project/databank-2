class IngestResponseEvent < ApplicationRecord
  belongs_to :external_delivery_attempt, optional: true

  enum :status, {
    matched: "matched",
    unmatched: "unmatched",
    invalid: "invalid"
  }, prefix: :event

  validates :status, presence: true
  validates :integration, presence: true
  validates :received_at, presence: true

  scope :orphaned, -> { where(status: %i[unmatched invalid]) }
end
