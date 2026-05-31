class CuratorDirectory
  class << self
    def core_emails
      raw = Rails.application.credentials.dig(:core_curators, :emails)
      raw = ENV["CORE_CURATOR_EMAILS"] if raw.blank?

      normalize_email_list(raw)
    end

    def core_email?(email)
      normalized_email = normalize_email(email)
      return false if normalized_email.blank?

      core_emails.include?(normalized_email)
    end

    def managed_email?(email)
      normalized_email = normalize_email(email)
      return false if normalized_email.blank?

      ManagedCurator.exists?(email: normalized_email)
    end

    def includes_email?(email)
      core_email?(email) || managed_email?(email)
    end

    def managed_emails
      ManagedCurator.order(:email).pluck(:email)
    end

    def review_recipients
      dynamic_user_emails = User.where(role: %w[admin curator]).pluck(:email)

      normalize_email_list(core_emails + managed_emails + dynamic_user_emails)
    end

    private

    def normalize_email_list(values)
      Array(values)
        .flat_map { |value| value.to_s.split(",") }
        .map { |value| normalize_email(value) }
        .reject(&:blank?)
        .uniq
    end

    def normalize_email(email)
      email.to_s.strip.downcase
    end
  end
end
