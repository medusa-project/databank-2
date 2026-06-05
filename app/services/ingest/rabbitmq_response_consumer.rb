require "json"

begin
  require "bunny"
rescue LoadError
  # Bunny is optional unless ingest response processing is enabled.
end

module Ingest
  class RabbitmqResponseConsumer
    Result = Struct.new(:processed, :matched, :unmatched, :invalid, keyword_init: true)

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def enabled?
      responses_enabled? && rabbitmq_url.present? && response_queue.present? && defined?(Bunny)
    end

    def consume_batch(max_messages: default_batch_size)
      return Result.new(processed: 0, matched: 0, unmatched: 0, invalid: 0) unless enabled?

      session = Bunny.new(rabbitmq_url)
      session.start

      channel = session.create_channel
      queue = channel.queue(response_queue, durable: true)
      limit = [ max_messages.to_i, 1 ].max

      result = Result.new(processed: 0, matched: 0, unmatched: 0, invalid: 0)

      limit.times do
        delivery_info, _properties, payload = queue.pop(manual_ack: true)
        break if payload.blank?

        outcome = process_payload(payload)
        channel.ack(delivery_info.delivery_tag) if delivery_info

        result.processed += 1
        case outcome
        when :matched then result.matched += 1
        when :unmatched then result.unmatched += 1
        else
          result.invalid += 1
        end
      end

      result
    rescue StandardError => e
      @logger.error("Ingest::RabbitmqResponseConsumer consume_batch failed: #{e.class}: #{e.message}")
      raise
    ensure
      session&.close if session&.open?
    end

    def process_payload(raw_payload)
      response = JSON.parse(raw_payload)
      correlation_key = extract_correlation_key(response)

      if correlation_key.blank?
        record_event!(
          status: :unmatched,
          correlation_key: nil,
          payload: response,
          raw_payload: raw_payload,
          error_message: "Missing correlation key"
        )
        @logger.warn("Ingest::RabbitmqResponseConsumer unmatched response: missing correlation key")
        return :unmatched
      end

      attempt = ExternalDeliveryAttempt.for_ingest_correlation(correlation_key).first
      unless attempt
        record_event!(
          status: :unmatched,
          correlation_key: correlation_key,
          payload: response,
          raw_payload: raw_payload,
          error_message: "No matching delivery attempt"
        )
        @logger.warn("Ingest::RabbitmqResponseConsumer unmatched response for correlation key #{correlation_key}")
        return :unmatched
      end

      attempt.apply_ingest_response!(response)
      record_event!(
        status: :matched,
        correlation_key: correlation_key,
        external_delivery_attempt: attempt,
        payload: response,
        raw_payload: raw_payload
      )
      :matched
    rescue JSON::ParserError
      record_event!(
        status: :invalid,
        correlation_key: nil,
        payload: {},
        raw_payload: raw_payload,
        error_message: "Invalid JSON payload"
      )
      @logger.warn("Ingest::RabbitmqResponseConsumer invalid response payload")
      :invalid
    rescue StandardError => e
      record_event!(
        status: :invalid,
        correlation_key: nil,
        payload: {},
        raw_payload: raw_payload,
        error_message: "Processing failure: #{e.class}"
      )
      @logger.error("Ingest::RabbitmqResponseConsumer process_payload failed: #{e.class}: #{e.message}")
      :invalid
    end

    private

    def extract_correlation_key(response)
      response["correlation_key"].presence ||
        response["idempotency_key"].presence ||
        response.dig("pass_through", "correlation_key").presence ||
        response["staging_key"].presence
    end

    def responses_enabled?
      IdbConfig.fetch(:ingest, :responses_enabled, default: "false").casecmp("true").zero?
    end

    def rabbitmq_url
      IdbConfig.fetch(:ingest, :rabbitmq_url, default: "").to_s.strip
    end

    def response_queue
      IdbConfig.fetch(:ingest, :responses_queue, default: "").to_s.strip
    end

    def default_batch_size
      IdbConfig.fetch(:ingest, :response_batch_size, default: "50").to_i
    end

    def record_event!(status:, correlation_key:, payload:, raw_payload:, error_message: nil, external_delivery_attempt: nil)
      IngestResponseEvent.create!(
        status: status,
        integration: "ingest",
        correlation_key: correlation_key,
        external_delivery_attempt: external_delivery_attempt,
        received_at: Time.current,
        payload: payload,
        raw_payload: raw_payload,
        error_message: error_message
      )
    rescue StandardError => e
      @logger.error("Ingest::RabbitmqResponseConsumer record_event failed: #{e.class}: #{e.message}")
    end
  end
end
