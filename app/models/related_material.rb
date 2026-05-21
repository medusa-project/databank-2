class RelatedMaterial < ApplicationRecord
  belongs_to :dataset

  validates :title, presence: true
  validates :uri, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
