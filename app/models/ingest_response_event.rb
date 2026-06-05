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
  scope :unresolved_orphaned, -> { orphaned.where(acknowledged_at: nil) }

  def acknowledge!(by_email:, note: nil)
    update!(
      acknowledged_at: Time.current,
      acknowledged_by_email: by_email.to_s.strip.downcase.presence,
      acknowledged_note: note.to_s.strip.presence
    )
  end
end
