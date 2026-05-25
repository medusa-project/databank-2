class Guide::Section < ApplicationRecord
  has_many :guide_items, dependent: :destroy, class_name: "Guide::Item", foreign_key: :section_id, inverse_of: :guide_section

  has_rich_text :body

  scope :ordered, -> { order(Arel.sql("COALESCE(ordinal, 2147483647) ASC, id ASC")) }

  def ordered_children
    guide_items.ordered
  end
end
