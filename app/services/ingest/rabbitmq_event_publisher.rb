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
      ingest_events_enabled? && rabbitmq_url.present? && requests_queue.present? && defined?(Bunny)
    end

    def publish_datafile(datafile, correlation_key:)
      return false unless enabled?

      payload = ingest_payload(datafile, correlation_key: correlation_key)
      session = Bunny.new(rabbitmq_url)
      session.start

      channel = session.create_channel
      channel.queue(requests_queue, durable: true)
      channel.confirm_select
      channel.default_exchange.publish(JSON.generate(payload),
                       routing_key: requests_queue,
                       content_type: "application/json",
                       persistent: true)
      raise IOError, "Medusa ingest request was not confirmed by RabbitMQ" unless channel.wait_for_confirms

      true
    rescue StandardError => e
      @logger.warn("Ingest::RabbitmqEventPublisher failed: #{e.class}: #{e.message}")
      false
    ensure
      session&.close if session&.open?
    end

    private

    def ingest_payload(datafile, correlation_key:)
      raise ArgumentError, "Ingest correlation key is missing" if correlation_key.blank?
      raise ArgumentError, "Datafile name is missing" if datafile.binary_name.blank?

      stage_datafile!(datafile)
      dataset = datafile.dataset
      {
        operation: "ingest",
        staging_key: datafile.storage_key_with_prefix,
        target_key: File.join(dataset.key, datafile.binary_name),
        pass_through: {
          dataset_id: dataset.id,
          dataset_key: dataset.key,
          datafile_id: datafile.id,
          datafile_web_id: datafile.web_id,
          correlation_key: correlation_key
        }
      }
    end

    def stage_datafile!(datafile)
      draft_root = StorageManager.instance.draft_root
      if datafile.storage_root == draft_root.name && datafile.exists_on_storage?
        return
      end

      raise ArgumentError, "Datafile #{datafile.web_id} has no draft binary to ingest" unless datafile.binary.attached?

      key = File.join(datafile.web_id, datafile.binary_name)
      datafile.binary.open do |io|
        draft_root.copy_io_to(key, io, nil, datafile.binary.byte_size)
      end
      datafile.update!(storage_root: draft_root.name, storage_key: key)
    end

    def ingest_events_enabled?
      IdbConfig.fetch(:ingest, :events_enabled, default: "false").to_s.casecmp("true").zero?
    end

    def rabbitmq_url
      IdbConfig.fetch(:ingest, :rabbitmq_url, default: "").to_s.strip
    end

    def requests_queue
      IdbConfig.fetch(:ingest, :requests_queue, default: "").to_s.strip
    end
  end
end
