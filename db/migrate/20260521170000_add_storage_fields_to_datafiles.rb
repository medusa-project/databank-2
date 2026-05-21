class AddStorageFieldsToDatafiles < ActiveRecord::Migration[8.1]
  def change
    add_column :datafiles, :medusa_id, :string
    add_column :datafiles, :storage_root, :string
    add_column :datafiles, :storage_key, :string

    add_index :datafiles, [ :storage_root, :storage_key ], name: "index_datafiles_on_storage_location"
  end
end
