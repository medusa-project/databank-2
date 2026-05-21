module Migration
  class RunRecorder
    def initialize(run_type:, label: nil, source_since: nil, source_until: nil, bundle_path: nil, checksum_path: nil, manifest_path: nil, details: {})
      @run_type = run_type
      @label = label
      @source_since = source_since
      @source_until = source_until
      @bundle_path = bundle_path
      @checksum_path = checksum_path
      @manifest_path = manifest_path
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
        details: details
      )
    end

    def finish!(run:, summary:)
      run.update!(
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
        details: run.details.merge(summary: compact_summary(summary))
      )
    end

    private

    attr_reader :run_type, :label, :source_since, :source_until, :bundle_path, :checksum_path, :manifest_path, :details

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
  end
end
