class DatasetDownloadTally < ApplicationRecord
  validates :dataset_key, :download_date, presence: true
  validates :tally, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
