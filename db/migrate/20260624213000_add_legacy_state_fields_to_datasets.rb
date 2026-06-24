class AddLegacyStateFieldsToDatasets < ActiveRecord::Migration[8.1]
  def change
    add_column :datasets, :legacy_publication_state, :string unless column_exists?(:datasets, :legacy_publication_state)
    add_column :datasets, :hold_state, :string unless column_exists?(:datasets, :hold_state)
    add_column :datasets, :tombstone_date, :date unless column_exists?(:datasets, :tombstone_date)

    add_index :datasets, :legacy_publication_state unless index_exists?(:datasets, :legacy_publication_state)
    add_index :datasets, :hold_state unless index_exists?(:datasets, :hold_state)
    add_index :datasets, :tombstone_date unless index_exists?(:datasets, :tombstone_date)
  end
end
