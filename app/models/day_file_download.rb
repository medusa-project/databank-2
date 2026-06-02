class DayFileDownload < ApplicationRecord
  validates :ip_address, :file_web_id, :download_date, :dataset_key, presence: true
end
