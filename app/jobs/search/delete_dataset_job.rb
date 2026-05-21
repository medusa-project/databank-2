module Search
  class DeleteDatasetJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(dataset_key)
      return if dataset_key.blank?

      success = SolrIndexer.new.delete_dataset(dataset_key)
      return if success

      message = "Search::DeleteDatasetJob failed"
      Rails.logger.warn(
        {
          event: "search.delete_dataset.failed",
          job_id: job_id,
          dataset_key: dataset_key,
          executions: executions,
          message: message
        }.to_json
      )
      raise StandardError, message
    end
  end
end
