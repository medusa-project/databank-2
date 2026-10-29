module MarksReviewRequestsModified
  extend ActiveSupport::Concern

  included do
    after_commit :mark_review_requests_modified, on: %i[create update destroy]
  end

  private

  def mark_review_requests_modified
    dataset&.mark_review_requests_modified!
  end
end
