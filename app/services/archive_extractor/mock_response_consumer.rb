module ArchiveExtractor
  class MockResponseConsumer
    Summary = Struct.new(:processed, :succeeded, :failed, :skipped, keyword_init: true)

    def poll_responses(batch_size: 10)
      Summary.new(processed: 0, succeeded: 0, failed: 0, skipped: batch_size.to_i)
    end
  end
end
