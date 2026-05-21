class Creator < ApplicationRecord
  belongs_to :dataset

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
