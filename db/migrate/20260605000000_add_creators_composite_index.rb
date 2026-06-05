class AddCreatorsCompositeIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :creators, [ :dataset_id, :email ]
  end
end
