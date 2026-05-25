class Guide::Subitem < ApplicationRecord
  belongs_to :guide_item, class_name: "Guide::Item", foreign_key: :item_id, inverse_of: :guide_subitems, optional: true

  has_rich_text :body

  scope :ordered, -> { order(Arel.sql("COALESCE(ordinal, 2147483647) ASC, id ASC")) }
end
