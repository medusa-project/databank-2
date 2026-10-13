module Ingest
  class PublishDatasetEventJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(dataset_id, replay_idempotency_key = nil, datafile_id = nil)
      dataset = Dataset.find_by(id: dataset_id)
      return unless dataset

      key = idempotency_key_for(dataset, replay_idempotency_key)
      if datafile_id && already_succeeded?(dataset: dataset, idempotency_key: key)
        build_attempt(
          dataset: dataset,
          status: :skipped,
          idempotency_key: key,
          correlation_key: key,
          details: { reason: "already_succeeded", datafile_id: datafile_id }
        )
        return
      end

      publisher = RabbitmqEventPublisher.new
      unless publisher.enabled?
        attempt_record = build_attempt(dataset: dataset, status: :started, idempotency_key: key, correlation_key: key)
        attempt_record.update!(status: :skipped, details: { reason: "integration_disabled" })
        return
      end

      files = dataset.datafiles.where.not(storage_root: "medusa").or(dataset.datafiles.where(storage_root: nil))
      files = files.where(id: datafile_id) if datafile_id
      if files.empty?
        raise ArgumentError, "Requested datafile is unavailable for ingest" if datafile_id

        build_attempt(
          dataset: dataset, status: :skipped, idempotency_key: key, correlation_key: key,
          details: { reason: "no_files_to_ingest" }
        )
        return
      end
      names = dataset.datafiles.pluck(:binary_name)
      raise ArgumentError, "Datafiles have duplicate Medusa target names" unless names.uniq.size == names.size

      files.order(:id).each do |datafile|
        file_key = datafile_id ? key : "#{key}:datafile:#{datafile.id}"
        next if already_succeeded?(dataset: dataset, idempotency_key: file_key)

        publish_file!(publisher, dataset, datafile, file_key)
      end
    end

    private

    def publish_file!(publisher, dataset, datafile, key)
      attempt_record = build_attempt(
        dataset: dataset, status: :started, idempotency_key: key, correlation_key: key,
        details: { datafile_id: datafile.id, datafile_web_id: datafile.web_id }
      )
      success = publisher.publish_datafile(datafile, correlation_key: key)
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
          dataset_id: dataset.id,
          dataset_key: dataset.key,
          executions: executions,
          message: message
        }.to_json
      )
      raise StandardError, message
    end

    def build_attempt(dataset:, status:, idempotency_key:, correlation_key:, details: {})
      ExternalDeliveryAttempt.create!(
        dataset: dataset,
        integration: :ingest,
        event_name: "dataset.published",
        status: status,
        attempt: [ executions.to_i, 1 ].max,
        job_id: job_id,
        idempotency_key: idempotency_key,
        correlation_key: correlation_key,
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
