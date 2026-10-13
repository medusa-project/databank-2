class AddAllMedusaToDatasets < ActiveRecord::Migration[8.1]
  def change
    add_column :datasets, :all_medusa, :boolean, default: false, null: false
  end
end
