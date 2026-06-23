class CreateRelatedMaterialRelationships < ActiveRecord::Migration[8.1]
  class MigrationRelatedMaterial < ApplicationRecord
    self.table_name = "related_materials"
  end

  class MigrationRelatedMaterialRelationship < ApplicationRecord
    self.table_name = "related_material_relationships"
  end

  RELATION_TYPE_OPTIONS = [
    "IsSupplementTo",
    "IsSupplementedBy",
    "IsCitedBy",
    "IsPreviousVersionOf",
    "IsNewVersionOf"
  ].freeze

  def up
    create_table :related_material_relationships do |t|
      t.references :related_material, null: false, foreign_key: true
      t.string :relation_type, null: false
      t.integer :position, null: false, default: 1
      t.timestamps
    end

    add_index :related_material_relationships,
              [ :related_material_id, :relation_type ],
              unique: true,
              name: "idx_related_material_relationships_unique_relation"

    backfill_relationship_rows!
  end

  def down
    drop_table :related_material_relationships
  end

  private

  def backfill_relationship_rows!
    MigrationRelatedMaterial.reset_column_information
    MigrationRelatedMaterialRelationship.reset_column_information

    now = Time.current

    MigrationRelatedMaterial.find_each do |material|
      relation_values = extract_relations(material)
      relation_values.each_with_index do |relation_type, index|
        MigrationRelatedMaterialRelationship.create!(
          related_material_id: material.id,
          relation_type: relation_type,
          position: index + 1,
          created_at: now,
          updated_at: now
        )
      end
    end
  end

  def extract_relations(material)
    values = []
    values.concat(material.datacite_list.to_s.split(","))
    values << material.relation_type if material.relation_type.present?

    values
      .map { |value| value.to_s.strip }
      .reject(&:blank?)
      .select { |value| RELATION_TYPE_OPTIONS.include?(value) }
      .uniq
  end
end
