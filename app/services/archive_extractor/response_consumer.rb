require "json"

begin
  require "aws-sdk-sqs"
rescue LoadError
  # SQS client dependency is optional until extractor integration is enabled.
end

module ArchiveExtractor
  class ResponseConsumer
    Summary = Struct.new(:processed, :succeeded, :failed, :skipped, keyword_init: true)

    def initialize(sqs_client: default_sqs_client, queue_url: Config.aws_sqs_queue_url, message_root: StorageManager.instance.message_root, logger: Rails.logger)
      @sqs_client = sqs_client
      @queue_url = queue_url
      @message_root = message_root
      @logger = logger
    end

    def poll_responses(batch_size: 10)
      return Summary.new(processed: 0, succeeded: 0, failed: 0, skipped: 0) unless pollable?

      response = @sqs_client.receive_message(queue_url: @queue_url, max_number_of_messages: [ batch_size.to_i, 10 ].min)
      messages = extract_messages(response)

      summary = Summary.new(processed: 0, succeeded: 0, failed: 0, skipped: 0)

      messages.each do |message|
        summary.processed += 1
        outcome = process_message(message)
        case outcome
        when :succeeded then summary.succeeded += 1
        when :skipped then summary.skipped += 1
        else
          summary.failed += 1
        end
      end

      summary
    rescue StandardError => e
      @logger.error("ArchiveExtractor::ResponseConsumer poll_responses failed: #{e.class}: #{e.message}")
      raise
    end

    private

    def default_sqs_client
      raise LoadError, "aws-sdk-sqs is not available" unless defined?(Aws::SQS::Client)

      Aws::SQS::Client.new(region: Config.aws_region)
    end

    def pollable?
      @queue_url.present? && !@message_root.nil?
    end

    def extract_messages(response)
      if response.respond_to?(:messages)
        Array(response.messages)
      elsif response.respond_to?(:data) && response.data.respond_to?(:messages)
        Array(response.data.messages)
      else
        []
      end
    end

    def process_message(message)
      envelope = parse_json(message.body)
      object_key = envelope["object_key"].to_s
      return acknowledge(message, :skipped) if object_key.blank?

      response_key = object_key.split("/").last
      response_text = read_response_file(response_key)
      return acknowledge(message, :failed) if response_text.nil?

      payload = parse_json(response_text)
      web_id = payload["web_id"].presence || response_key.split(".").first
      request = find_request_for_web_id(web_id)
      return finalize_without_request(message, response_key) if request.nil?

      persist_response!(request: request, envelope: envelope, payload: payload, raw_response: response_text)
      delete_response_file(response_key)
      acknowledge(message, :succeeded)
    rescue JSON::ParserError
      @logger.warn("ArchiveExtractor::ResponseConsumer invalid JSON payload received")
      acknowledge(message, :failed)
    rescue StandardError => e
      @logger.error("ArchiveExtractor::ResponseConsumer process_message failed: #{e.class}: #{e.message}")
      acknowledge(message, :failed)
    end

    def parse_json(text)
      JSON.parse(text.to_s)
    end

    def read_response_file(response_key)
      unless @message_root.exist?(response_key)
        @logger.warn("ArchiveExtractor response file not found for key #{response_key}")
        return nil
      end

      @message_root.as_string(response_key)
    end

    def delete_response_file(response_key)
      @message_root.delete_content(response_key) if @message_root.exist?(response_key)
    rescue StandardError => e
      @logger.warn("ArchiveExtractor::ResponseConsumer delete response file failed: #{e.class}: #{e.message}")
    end

    def find_request_for_web_id(web_id)
      return nil if web_id.blank?

      ArchiveExtractRequest.joins(:datafile).find_by(datafiles: { web_id: web_id })
    end

    def finalize_without_request(message, response_key)
      @logger.warn("ArchiveExtractor response has no matching request for #{response_key}")
      delete_response_file(response_key)
      acknowledge(message, :skipped)
    end

    def persist_response!(request:, envelope:, payload:, raw_response:)
      archive_response = request.archive_extract_response || request.build_archive_extract_response
      archive_response.status = payload["status"].presence || "error"
      archive_response.response = payload
      archive_response.save!

      archive_response.archive_extract_errors.delete_all
      extract_errors(payload: payload, envelope: envelope).each do |error|
        archive_response.archive_extract_errors.create!(
          error_type: error["error_type"].presence,
          error_report: error["report"].presence || error.to_json
        )
      end

      request.update!(
        status: response_success?(payload: payload, envelope: envelope) ? :success : :failed,
        response_at: Time.current,
        raw_response: raw_response
      )

      request.datafile.update!(
        peek_type: payload["peek_type"],
        peek_content: payload["peek_text"]
      )
    end

    def extract_errors(payload:, envelope:)
      response_errors = Array(payload["error"]).compact.map { |e| normalize_error(e) }
      envelope_errors = Array(envelope["error"]).compact.map { |e| normalize_error(e) }
      response_errors + envelope_errors
    end

    def normalize_error(error)
      case error
      when Hash then error.stringify_keys
      else
        { "error_type" => "unknown", "report" => error.to_s }
      end
    end

    def response_success?(payload:, envelope:)
      payload_status = payload["status"].to_s.casecmp("success").zero?
      envelope_status = envelope["s3_status"].to_s.casecmp("success").zero?
      payload_status && envelope_status
    end

    def acknowledge(message, outcome)
      @sqs_client.delete_message(queue_url: @queue_url, receipt_handle: message.receipt_handle)
      outcome
    rescue StandardError => e
      @logger.error("ArchiveExtractor::ResponseConsumer acknowledge failed: #{e.class}: #{e.message}")
      :failed
    end
  end
end
