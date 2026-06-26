class CreateNestedItems < ActiveRecord::Migration[8.1]
  def change
    create_table :nested_items do |t|
      t.references :datafile, null: false, foreign_key: true
      t.bigint :parent_id
      t.string :item_name, null: false
      t.string :media_type
      t.bigint :size
      t.text :item_path
      t.boolean :is_directory, default: false

      t.timestamps
    end

    add_index :nested_items, [ :datafile_id, :item_name ]
    add_index :nested_items, [ :parent_id ]
    add_foreign_key :nested_items, :nested_items, column: :parent_id
  end
end
