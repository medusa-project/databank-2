class AddExtendedMetadataToDatasets < ActiveRecord::Migration[8.1]
  def change
    add_column :datasets, :keywords, :text
    add_column :datasets, :subject, :string
    add_column :datasets, :license, :string
    add_column :datasets, :publisher, :string
  end
end
