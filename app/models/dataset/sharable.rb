module Dataset::Sharable
  extend ActiveSupport::Concern

  included do
    has_one :share_code, dependent: :destroy
    after_save :revoke_ineligible_share_code
  end

  def sharing_link
    code = current_share_code
    return "N/A no current sharing link" unless code

    root_url = IdbConfig.fetch(:app, :root_url_text, default: "http://localhost:3000")
    Rails.application.routes.url_helpers.dataset_url(self, host: root_url, code: code)
  end

  def current_share_code
    current = share_code
    return unless current&.persisted?

    if current.created_at < 1.year.ago || files_publicly_readable_now?
      current.destroy!
      association(:share_code).reset
      return
    end

    current.code
  end

  def has_sharing_link?
    hold = hold_state_mode
    return false if hold == Dataset::HOLD_PERM_METADATA || hold == Dataset::HOLD_PERM_FILE

    current_share_code.present?
  end

  def valid_share_code?(code:)
    return false unless share_code_eligable?
    return false unless code.is_a?(String) && code.present?

    current = current_share_code
    current.present? && ActiveSupport::SecurityUtils.secure_compare(current, code)
  end

  def share_code_eligable?
    return false if hold_state_mode == Dataset::HOLD_PERM_METADATA || hold_state_mode == Dataset::HOLD_PERM_FILE

    return false if files_publicly_readable_now?

    true
  end

  private

  # Covers publication, release and permanent suppression, which all end in a save.
  def revoke_ineligible_share_code
    return if share_code_eligable?

    share_code&.destroy!
    association(:share_code).reset
  end
end
