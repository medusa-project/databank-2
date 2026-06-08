class ArchiveExtractRequest < ApplicationRecord
  belongs_to :datafile
  has_one :archive_extract_response, dependent: :destroy
  has_many :archive_extract_errors, through: :archive_extract_response

  enum :status, {
    pending: "pending",
    sent: "sent",
    success: "success",
    failed: "failed"
  }

  validates :datafile, presence: true
  validates :datafile_id, uniqueness: true
  validates :status, presence: true
end
