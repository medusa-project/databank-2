class AddVisibilityFilterIndexToDatasets < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_datasets_on_visibility_filter_columns".freeze

  def up
    add_index :datasets,
              [ :publication_state, :hold_state, :embargo, :release_date ],
              name: INDEX_NAME,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :datasets, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
