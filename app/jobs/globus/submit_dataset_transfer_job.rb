module Globus
  class SubmitDatasetTransferJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(dataset_id)
      dataset = Dataset.find_by(id: dataset_id)
      return unless dataset

      key = idempotency_key_for(dataset)
      if already_succeeded?(dataset: dataset, idempotency_key: key)
        build_attempt(
          dataset: dataset,
          status: :skipped,
          idempotency_key: key,
          details: { reason: "already_succeeded" }
        )
        return
      end

      service = TransferService.new
      attempt_record = build_attempt(dataset: dataset, status: :started, idempotency_key: key)
      unless service.enabled?
        attempt_record.update!(status: :skipped, details: { reason: "integration_disabled" })
        return
      end

      success = service.submit_dataset_transfer(dataset)
      if success
        attempt_record.update!(status: :succeeded)
        return
      end

      message = "Globus::SubmitDatasetTransferJob failed"
      attempt_record.update!(
        status: :failed,
        error_class: "TransferError",
        error_message: message
      )
      Rails.logger.warn(
        {
          event: "globus.submit_dataset_transfer.failed",
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
        integration: :globus,
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
        integration: :globus,
        event_name: "dataset.published",
        idempotency_key: idempotency_key
      ).where(dataset: dataset).exists?
    end

    def idempotency_key_for(dataset)
      published_at = dataset.published_at&.utc&.iso8601 || "unpublished"
      "dataset.published:#{dataset.id}:#{published_at}"
    end
  end
end
