require "digest"

module Ingest
  class SendHealthAlertsJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform
      return unless HealthSummary.alerts_enabled?

      recipients = HealthSummary.alert_recipients
      return if recipients.blank?

      latest_attempts_by_dataset.each do |dataset_id, attempt|
        dataset = Dataset.find_by(id: dataset_id)
        next unless dataset

        summary = HealthSummary.new(dataset: dataset, latest_attempt: attempt).call
        next if summary.blank? || summary[:alerts].blank?
        next unless send_allowed?(dataset: dataset, summary: summary)

        IngestHealthMailer.dataset_alert(dataset: dataset, summary: summary, recipients: recipients).deliver_later
      end
    end

    private

    def latest_attempts_by_dataset
      attempts = ExternalDeliveryAttempt
        .where(integration: :ingest, event_name: "dataset.published")
        .order(created_at: :desc)

      attempts.each_with_object({}) do |attempt, memo|
        memo[attempt.dataset_id] ||= attempt
      end
    end

    def send_allowed?(dataset:, summary:)
      key = cooldown_cache_key(dataset: dataset, summary: summary)
      return false if Rails.cache.read(key)

      Rails.cache.write(key, true, expires_in: HealthSummary.alert_cooldown_minutes.minutes)
      true
    end

    def cooldown_cache_key(dataset:, summary:)
      digest = Digest::SHA256.hexdigest(summary[:alerts].join("|"))
      "ingest.health.alert:dataset:#{dataset.id}:#{digest}"
    end
  end
end
