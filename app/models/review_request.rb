class ReviewRequest < ApplicationRecord
  belongs_to :dataset

  validates :requester_name, presence: true
  validates :requester_email, presence: true
  validates :requested_at, presence: true

  scope :latest_first, -> { order(requested_at: :desc, id: :desc) }
end
