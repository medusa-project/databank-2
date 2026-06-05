class CreateDatasetAccessGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :dataset_access_grants do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :email, null: false
      t.integer :access_level, null: false, default: 0

      t.timestamps
    end

    add_index :dataset_access_grants, [ :dataset_id, :email ], unique: true
    add_index :dataset_access_grants, [ :email, :access_level ]
  end
end
