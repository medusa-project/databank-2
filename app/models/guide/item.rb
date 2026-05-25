class Guide::Item < ApplicationRecord
  belongs_to :guide_section, class_name: "Guide::Section", foreign_key: :section_id, inverse_of: :guide_items, optional: true
  has_many :guide_subitems, dependent: :destroy, class_name: "Guide::Subitem", foreign_key: :item_id, inverse_of: :guide_item

  has_rich_text :body

  scope :ordered, -> { order(Arel.sql("COALESCE(ordinal, 2147483647) ASC, id ASC")) }

  def ordered_children
    guide_subitems.ordered
  end
end
