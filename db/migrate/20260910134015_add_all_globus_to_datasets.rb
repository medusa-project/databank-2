class AddAllGlobusToDatasets < ActiveRecord::Migration[8.1]
  def change
    add_column :datasets, :all_globus, :boolean, default: false, null: false
  end
end
