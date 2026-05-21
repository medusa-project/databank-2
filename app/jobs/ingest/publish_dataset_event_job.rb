module Ingest
  class PublishDatasetEventJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(dataset_id)
      dataset = Dataset.find_by(id: dataset_id)
      return unless dataset

      success = RabbitmqEventPublisher.new.publish_dataset_published(dataset)
      return if success

      message = "Ingest::PublishDatasetEventJob failed"
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
  end
end
