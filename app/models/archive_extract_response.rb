class ArchiveExtractResponse < ApplicationRecord
  belongs_to :archive_extract_request
  has_many :archive_extract_errors, dependent: :destroy

  validates :status, presence: true
end
