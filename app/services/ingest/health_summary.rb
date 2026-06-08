module Ingest
  class HealthSummary
    def initialize(dataset:, latest_attempt:, now: Time.current)
      @dataset = dataset
      @latest_attempt = latest_attempt
      @now = now
    end

    def call
      return nil unless @latest_attempt

      stale_minutes = self.class.stale_minutes
      orphan_lookback_minutes = self.class.orphan_lookback_minutes
      orphan_threshold = self.class.orphan_alert_threshold

      alerts = []
      freshness_message = nil
      health_state = "ok"

      if @latest_attempt.response_received_at.present?
        age_minutes = ((@now - @latest_attempt.response_received_at) / 60).floor
        freshness_message = "Latest Medusa response was received #{age_minutes} minute(s) ago."

        if age_minutes > stale_minutes
          alerts << "Latest Medusa response is stale (#{age_minutes} minutes old; threshold #{stale_minutes} minutes)."
        end
      else
        age_minutes = ((@now - @latest_attempt.created_at) / 60).floor
        freshness_message = "No Medusa response has been recorded yet; latest ingest attempt was #{age_minutes} minute(s) ago."

        if age_minutes > stale_minutes
          alerts << "No Medusa response recorded within stale threshold (#{stale_minutes} minutes)."
        end
      end

      if @latest_attempt.response_failed?
        health_state = "critical"
        alerts << "Latest Medusa response reported failure."
      end

      orphan_count = orphaned_responses_for_dataset(lookback_minutes: orphan_lookback_minutes)
      if orphan_threshold.positive? && orphan_count >= orphan_threshold
        alerts << "#{orphan_count} orphaned ingest response(s) in the last #{orphan_lookback_minutes} minutes (threshold #{orphan_threshold})."
      end

      health_state = "warning" if health_state == "ok" && alerts.any?

      {
        state: health_state,
        freshness_message: freshness_message,
        orphan_count: orphan_count,
        orphan_lookback_minutes: orphan_lookback_minutes,
        alerts: alerts
      }
    end

    def self.stale_minutes
      value = IdbConfig.fetch(:ingest, :health_response_stale_minutes, default: "60").to_i
      value.positive? ? value : 60
    end

    def self.orphan_lookback_minutes
      value = IdbConfig.fetch(:ingest, :health_orphan_lookback_minutes, default: "120").to_i
      value.positive? ? value : 120
    end

    def self.orphan_alert_threshold
      value = IdbConfig.fetch(:ingest, :health_orphan_alert_threshold, default: "1").to_i
      value.negative? ? 0 : value
    end

    def self.alerts_enabled?
      IdbConfig.fetch(:ingest, :health_alerts_enabled, default: "false").casecmp("true").zero?
    end

    def self.alert_recipients
      IdbConfig.fetch(:ingest, :health_alert_emails, default: "")
        .to_s
        .split(",")
        .map { |value| value.strip.downcase }
        .reject(&:blank?)
        .uniq
    end

    def self.alert_cooldown_minutes
      value = IdbConfig.fetch(:ingest, :health_alert_cooldown_minutes, default: "60").to_i
      value.positive? ? value : 60
    end

    private

    def orphaned_responses_for_dataset(lookback_minutes:)
      lower_bound = @now - lookback_minutes.minutes
      base = IngestResponseEvent.unresolved_orphaned.where(received_at: lower_bound..@now)
      correlation_pattern = "dataset.published:#{@dataset.id}:%"

      by_correlation = base.where("correlation_key LIKE ?", correlation_pattern)
      by_payload_dataset_id = base.where("payload -> 'pass_through' ->> 'dataset_id' = ?", @dataset.id.to_s)

      by_correlation.or(by_payload_dataset_id).count
    end
  end
end
