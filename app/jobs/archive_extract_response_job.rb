class ArchiveExtractResponseJob < ApplicationJob
  queue_as :default

  def perform(batch_size: 10)
    consumer = if ArchiveExtractor::Config.use_mocks?
      ArchiveExtractor::MockResponseConsumer.new
    else
      ArchiveExtractor::ResponseConsumer.new
    end

    consumer.poll_responses(batch_size: batch_size)
  end
end
