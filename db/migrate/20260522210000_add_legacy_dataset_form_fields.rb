class AddLegacyDatasetFormFields < ActiveRecord::Migration[8.1]
  def change
    change_table :datasets, bulk: true do |t|
      t.string :embargo
      t.date :release_date
      t.boolean :complete
      t.string :search
      t.string :dataset_version
      t.boolean :is_test, default: false, null: false
      t.boolean :is_import, default: false, null: false
      t.string :medusa_dataset_dir
      t.string :external_files_link
      t.text :external_files_note
      t.text :version_comment
    end
  end
end
