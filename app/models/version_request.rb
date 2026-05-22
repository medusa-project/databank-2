class VersionRequest < ApplicationRecord
  belongs_to :dataset
  belongs_to :approved_dataset, class_name: "Dataset", optional: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  validates :requester_email, presence: true
  validates :requester_name, presence: true
  validates :requested_at, presence: true
end
