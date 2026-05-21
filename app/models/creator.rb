class Creator < ApplicationRecord
  belongs_to :dataset

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  after_commit :enqueue_dataset_reindex

  private

  def enqueue_dataset_reindex
    Search::IndexDatasetJob.perform_later(dataset_id)
  end
end
