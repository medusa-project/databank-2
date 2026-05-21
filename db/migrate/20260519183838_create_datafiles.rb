class CreateDatafiles < ActiveRecord::Migration[8.1]
  def change
    create_table :datafiles do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :web_id
      t.string :binary_name
      t.bigint :binary_size
      t.text :description

      t.timestamps
    end
    add_index :datafiles, :web_id, unique: true
  end
end
