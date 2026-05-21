module Ingest
  class PublishDatasetEventJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(dataset_id, replay_idempotency_key = nil)
      dataset = Dataset.find_by(id: dataset_id)
      return unless dataset

      key = idempotency_key_for(dataset, replay_idempotency_key)
      if already_succeeded?(dataset: dataset, idempotency_key: key)
        build_attempt(
          dataset: dataset,
          status: :skipped,
          idempotency_key: key,
          details: { reason: "already_succeeded" }
        )
        return
      end

      publisher = RabbitmqEventPublisher.new
      attempt_record = build_attempt(dataset: dataset, status: :started, idempotency_key: key)

      unless publisher.enabled?
        attempt_record.update!(status: :skipped, details: { reason: "integration_disabled" })
        return
      end

      success = publisher.publish_dataset_published(dataset)
      if success
        attempt_record.update!(status: :succeeded)
        return
      end

      message = "Ingest::PublishDatasetEventJob failed"
      attempt_record.update!(
        status: :failed,
        error_class: "PublisherError",
        error_message: message
      )
      Rails.logger.warn(
        {
          event: "ingest.publish_dataset_event.failed",
          job_id: job_id,
          dataset_id: dataset_id,
          dataset_key: dataset.key,
          executions: executions,
          message: message
        }.to_json
      )
      raise StandardError, message
    end

    private

    def build_attempt(dataset:, status:, idempotency_key:, details: {})
      ExternalDeliveryAttempt.create!(
        dataset: dataset,
        integration: :ingest,
        event_name: "dataset.published",
        status: status,
        attempt: [ executions.to_i, 1 ].max,
        job_id: job_id,
        idempotency_key: idempotency_key,
        details: details
      )
    end

    def already_succeeded?(dataset:, idempotency_key:)
      ExternalDeliveryAttempt.succeeded_for(
        integration: :ingest,
        event_name: "dataset.published",
        idempotency_key: idempotency_key
      ).where(dataset: dataset).exists?
    end

    def idempotency_key_for(dataset, replay_idempotency_key = nil)
      return replay_idempotency_key if replay_idempotency_key.present?

      published_at = dataset.published_at&.utc&.iso8601 || "unpublished"
      "dataset.published:#{dataset.id}:#{published_at}"
    end
  end
end
