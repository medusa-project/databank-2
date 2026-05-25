class CreateGuidesTables < ActiveRecord::Migration[8.1]
  def change
    create_table :guide_sections do |t|
      t.string :anchor
      t.string :label
      t.integer :ordinal
      t.boolean :public, default: false, null: false
      t.string :heading
      t.timestamps
    end

    create_table :guide_items do |t|
      t.references :section, foreign_key: { to_table: :guide_sections }
      t.string :anchor
      t.string :label
      t.integer :ordinal
      t.boolean :public, default: false, null: false
      t.string :heading
      t.timestamps
    end

    create_table :guide_subitems do |t|
      t.references :item, foreign_key: { to_table: :guide_items }
      t.string :anchor
      t.string :label
      t.integer :ordinal
      t.boolean :public, default: false, null: false
      t.string :heading
      t.timestamps
    end

    add_index :guide_sections, :anchor
    add_index :guide_items, :anchor
    add_index :guide_subitems, :anchor
  end
end
