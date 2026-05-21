module Search
  class IndexDatasetJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(dataset_id)
      dataset = Dataset.find_by(id: dataset_id)
      return unless dataset

      success = SolrIndexer.new.index_dataset(dataset)
      return if success

      message = "Search::IndexDatasetJob failed"
      Rails.logger.warn(
        {
          event: "search.index_dataset.failed",
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
