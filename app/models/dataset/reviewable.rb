module Dataset::Reviewable
  extend ActiveSupport::Concern

  included do
    after_update :mark_review_requests_modified, if: :saved_changes?
  end

  def latest_review_request
    review_requests.latest_first.first
  end

  def has_unmodified_review?
    latest = latest_review_request
    latest.present? && !latest.modified?
  end

  def mark_review_requests_modified!
    review_requests.where(modified: false).update_all(modified: true, updated_at: Time.current)
  end

  def in_pre_publication_review?
    draft? && latest_review_request.present?
  end

  private

  def mark_review_requests_modified
    mark_review_requests_modified! if review_requests.exists?
  end
end
