class AddSuppressChangelogToDatasets < ActiveRecord::Migration[8.1]
  def change
    add_column :datasets, :suppress_changelog, :boolean, null: false, default: false
  end
end
