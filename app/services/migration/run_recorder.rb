require "json"

module Migration
  class RunRecorder
    DEFAULT_FINISH_RETRY_ATTEMPTS = 5
    DEFAULT_FINISH_RETRY_DELAY_SECONDS = 2.0

    def initialize(run_type:, label: nil, source_since: nil, source_until: nil, bundle_path: nil, checksum_path: nil, manifest_path: nil, report_path: nil, details: {})
      @run_type = run_type
      @label = label
      @source_since = source_since
      @source_until = source_until
      @bundle_path = bundle_path
      @checksum_path = checksum_path
      @manifest_path = manifest_path
      @report_path = report_path
      @details = details
    end

    def start!
      MigrationRun.create!(
        run_type: run_type,
        status: "started",
        label: label,
        source_since: source_since,
        source_until: source_until,
        bundle_path: bundle_path,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        started_at: Time.current,
        details: details.merge(report_path: report_path&.to_s)
      )
    end

    def finish!(run:, summary:)
      attributes = {
        status: final_status(summary),
        created_count: summary[:created].to_i,
        updated_count: summary[:updated].to_i,
        skipped_count: summary[:skipped_existing].to_i,
        failed_count: summary[:failed].to_i,
        would_create_count: summary[:would_create].to_i,
        would_update_count: summary[:would_update].to_i,
        processed_count: summary[:processed_count].to_i,
        expected_count: summary[:expected_record_count],
        validation_error: summary[:validation_error],
        completed_at: Time.current,
        details: run.details.merge(
          summary: compact_summary(summary),
          report_artifact: report_artifact_details
        )
      }

      with_finish_retry do
        run.update!(attributes)
      end
    end

    private

    attr_reader :run_type, :label, :source_since, :source_until, :bundle_path, :checksum_path, :manifest_path, :report_path, :details

    def final_status(summary)
      return "failed" if summary[:validation_error].present?
      return "failed" if summary[:failed].to_i.positive?

      "completed"
    end

    def compact_summary(summary)
      {
        bundle_path: summary[:bundle_path],
        created: summary[:created],
        updated: summary[:updated],
        skipped_existing: summary[:skipped_existing],
        failed: summary[:failed],
        would_create: summary[:would_create],
        would_update: summary[:would_update],
        processed_count: summary[:processed_count],
        expected_record_count: summary[:expected_record_count],
        checksum: summary[:checksum],
        source_since: summary[:source_since],
        source_until: summary[:source_until]
      }
    end

    def report_artifact_details
      return nil if report_path.blank?

      payload = JSON.parse(File.read(report_path))
      {
        path: report_path.to_s,
        generated_at: payload["generated_at"],
        import_type: payload["import_type"],
        bundle_path: payload["bundle_path"],
        checksum_path: payload["checksum_path"],
        manifest_path: payload["manifest_path"],
        summary: compact_report_summary(payload["summary"] || {})
      }
    rescue StandardError => e
      {
        path: report_path.to_s,
        error: e.message
      }
    end

    def compact_report_summary(summary)
      {
        created: summary["created"],
        updated: summary["updated"],
        skipped_existing: summary["skipped_existing"],
        would_create: summary["would_create"],
        would_update: summary["would_update"],
        failed: summary["failed"],
        processed_count: summary["processed_count"],
        expected_record_count: summary["expected_record_count"],
        validation_error: summary["validation_error"]
      }
    end

    def with_finish_retry
      attempts = configured_finish_retry_attempts
      delay_seconds = configured_finish_retry_delay_seconds

      begin
        yield
      rescue StandardError => e
        raise unless transient_database_error?(e)

        attempts -= 1
        if attempts.positive?
          warn "Migration run completion retrying after transient DB error: #{e.message}"
          reset_connections_after_transient_error
          sleep(delay_seconds)
          retry
        end

        warn "Migration run completion unavailable after retries: #{e.message}"
      end
    end

    def transient_database_error?(error)
      return true if error.is_a?(ActiveRecord::ConnectionNotEstablished)

      if defined?(PG::ConnectionBad) && error.is_a?(PG::ConnectionBad)
        return true
      end

      if error.is_a?(ActiveRecord::StatementInvalid)
        message = error.message.to_s.downcase
        return true if message.include?("recovery mode")
        return true if message.include?("connection")
      end

      false
    end

    def reset_connections_after_transient_error
      if ActiveRecord::Base.respond_to?(:clear_active_connections!)
        ActiveRecord::Base.clear_active_connections!
      elsif ActiveRecord::Base.connection_handler.respond_to?(:clear_active_connections!)
        ActiveRecord::Base.connection_handler.clear_active_connections!
      else
        ActiveRecord::Base.connection_pool.release_connection
      end
    rescue StandardError
      nil
    end

    def configured_finish_retry_attempts
      raw = ENV["MIGRATION_RUN_FINISH_RETRY_ATTEMPTS"]
      parsed = Integer(raw, exception: false)
      return DEFAULT_FINISH_RETRY_ATTEMPTS if parsed.nil? || parsed <= 0

      parsed
    end

    def configured_finish_retry_delay_seconds
      raw = ENV["MIGRATION_RUN_FINISH_RETRY_DELAY_SECONDS"]
      return DEFAULT_FINISH_RETRY_DELAY_SECONDS if raw.blank?

      parsed = Float(raw, exception: false)
      return DEFAULT_FINISH_RETRY_DELAY_SECONDS if parsed.nil? || parsed.negative?

      parsed
    end
  end
end
