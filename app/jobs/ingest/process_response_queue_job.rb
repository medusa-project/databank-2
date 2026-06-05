module Ingest
  class ProcessResponseQueueJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(max_messages = nil)
      consumer = RabbitmqResponseConsumer.new
      return unless consumer.enabled?

      limit = max_messages.presence || IdbConfig.fetch(:ingest, :response_batch_size, default: "50").to_i
      result = consumer.consume_batch(max_messages: limit)

      Rails.logger.info(
        {
          event: "ingest.response_queue.processed",
          processed: result.processed,
          matched: result.matched,
          unmatched: result.unmatched,
          invalid: result.invalid
        }.to_json
      )
    end
  end
end
