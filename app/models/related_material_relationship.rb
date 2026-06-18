class RelatedMaterialRelationship < ApplicationRecord
  belongs_to :related_material

  validates :relation_type, presence: true, inclusion: { in: RelatedMaterial::RELATION_TYPE_OPTIONS }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
end
