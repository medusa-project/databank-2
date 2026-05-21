class ExternalDeliveryAttempt < ApplicationRecord
  belongs_to :dataset

  enum :integration, {
    ingest: "ingest",
    globus: "globus"
  }

  enum :status, {
    started: "started",
    skipped: "skipped",
    succeeded: "succeeded",
    failed: "failed"
  }

  validates :integration, presence: true
  validates :event_name, presence: true
  validates :status, presence: true
  validates :attempt, numericality: { only_integer: true, greater_than: 0 }
  validates :idempotency_key, presence: true

  scope :succeeded_for, lambda { |integration:, event_name:, idempotency_key:|
    where(
      integration: integration,
      event_name: event_name,
      idempotency_key: idempotency_key,
      status: :succeeded
    )
  }
end
