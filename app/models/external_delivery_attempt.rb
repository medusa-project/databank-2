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

  enum :response_status, {
    pending: "pending",
    succeeded: "succeeded",
    failed: "failed",
    orphaned: "orphaned"
  }, prefix: :response

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

  scope :for_ingest_correlation, lambda { |correlation_key|
    where(integration: :ingest, correlation_key: correlation_key)
      .order(created_at: :desc, id: :desc)
  }

  def apply_ingest_response!(response)
    response_hash = response.deep_stringify_keys
    response_state = response_success?(response_hash) ? :succeeded : :failed

    attrs = {
      response_status: response_state,
      response_received_at: Time.current,
      response_uuid: extract_uuid(response_hash),
      response_staging_key: extract_staging_key(response_hash),
      response_target_key: extract_target_key(response_hash),
      response_payload: response_hash
    }

    if response_state == :failed
      attrs[:status] = :failed
      attrs[:error_class] = "MedusaResponseError"
      attrs[:error_message] = extract_error_message(response_hash)
    end

    update!(attrs)
  end

  private

  def response_success?(response_hash)
    status = response_hash["status"].to_s.downcase
    request_status = response_hash["request_status"].to_s.downcase
    success_value = response_hash["success"]

    return true if success_value == true
    return true if %w[ok success succeeded].include?(status)
    return true if %w[ok success succeeded].include?(request_status)

    false
  end

  def extract_uuid(response_hash)
    response_hash["uuid"].presence || response_hash["medusa_uuid"].presence
  end

  def extract_staging_key(response_hash)
    response_hash["staging_key"].presence || response_hash.dig("pass_through", "staging_key").presence
  end

  def extract_target_key(response_hash)
    response_hash["target_key"].presence ||
      response_hash["medusa_key"].presence ||
      response_hash.dig("pass_through", "target_key").presence
  end

  def extract_error_message(response_hash)
    response_hash["error_message"].presence ||
      response_hash["error"].presence ||
      response_hash["message"].presence ||
      "Medusa ingest response reported failure"
  end
end
