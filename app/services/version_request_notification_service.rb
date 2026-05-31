class VersionRequestNotificationService
  def self.request_submitted(version_request:, dataset:)
    new.request_submitted(version_request: version_request, dataset: dataset)
  end

  def self.request_approved(version_request:, dataset:, approved_dataset:)
    new.request_approved(version_request: version_request, dataset: dataset, approved_dataset: approved_dataset)
  end

  def request_submitted(version_request:, dataset:)
    recipients = curator_recipients

    if recipients.any?
      VersionRequestMailer.request_submitted(
        version_request: version_request,
        dataset: dataset,
        recipients: recipients
      ).deliver_now
    end

    VersionRequestMailer.request_acknowledged(
      version_request: version_request,
      dataset: dataset
    ).deliver_now
  rescue StandardError => e
    Rails.logger.warn("version request submission mail failed for dataset #{dataset.key}: #{e.class}: #{e.message}")
  end

  def request_approved(version_request:, dataset:, approved_dataset:)
    VersionRequestMailer.request_approved(
      version_request: version_request,
      dataset: dataset,
      approved_dataset: approved_dataset
    ).deliver_now
  rescue StandardError => e
    Rails.logger.warn("version request approval mail failed for dataset #{dataset.key}: #{e.class}: #{e.message}")
  end

  private

  def curator_recipients
    configured = ENV["VERSION_REQUEST_REVIEW_EMAILS"].to_s.split(",").map(&:strip).reject(&:blank?)
    return configured if configured.any?

    CuratorDirectory.review_recipients
  end
end
