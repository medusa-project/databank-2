class ReviewRequest < ApplicationRecord
  belongs_to :dataset

  validates :requester_name, presence: true
  validates :requester_email, presence: true
  validates :requested_at, presence: true
end
