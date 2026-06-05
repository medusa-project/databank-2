require "json"

begin
  require "bunny"
rescue LoadError
  # Bunny is optional unless ingest publishing is enabled.
end

module Ingest
  class RabbitmqEventPublisher
    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def enabled?
      ingest_events_enabled? && rabbitmq_url.present? && defined?(Bunny)
    end

    def publish_dataset_published(dataset, correlation_key: nil)
      return false unless enabled?

      session = Bunny.new(rabbitmq_url)
      session.start

      channel = session.create_channel
      exchange = channel.topic(exchange_name, durable: true)
      exchange.publish(JSON.generate(event_payload(dataset, correlation_key: correlation_key)),
                       routing_key: routing_key,
                       content_type: "application/json",
                       persistent: true)
      true
    rescue StandardError => e
      @logger.warn("Ingest::RabbitmqEventPublisher failed: #{e.class}: #{e.message}")
      false
    ensure
      session&.close if session&.open?
    end

    private

    def event_payload(dataset, correlation_key: nil)
      {
        event: "dataset.published",
        emitted_at: Time.current.utc.iso8601,
        correlation_key: correlation_key,
        pass_through: {
          dataset_id: dataset.id,
          dataset_key: dataset.key,
          correlation_key: correlation_key
        },
        dataset: {
          id: dataset.id,
          key: dataset.key,
          identifier: dataset.identifier,
          title: dataset.title,
          publication_state: dataset.publication_state,
          published_at: dataset.published_at&.utc&.iso8601
        }
      }
    end

    def ingest_events_enabled?
      IdbConfig.fetch(:ingest, :events_enabled, default: "false").casecmp("true").zero?
    end

    def rabbitmq_url
      IdbConfig.fetch(:ingest, :rabbitmq_url, default: "").to_s.strip
    end

    def exchange_name
      IdbConfig.fetch(:ingest, :events_exchange, default: "databank.ingest")
    end

    def routing_key
      IdbConfig.fetch(:ingest, :events_routing_key, default: "dataset.published")
    end
  end
end
