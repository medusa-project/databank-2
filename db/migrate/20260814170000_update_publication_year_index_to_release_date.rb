class UpdatePublicationYearIndexToReleaseDate < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  OLD_INDEX_NAME = "index_datasets_on_effective_publication_year".freeze
  NEW_INDEX_NAME = "index_datasets_on_release_year".freeze
  NEW_YEAR_EXPRESSION = "(EXTRACT(YEAR FROM release_date)::int)".freeze

  def up
    remove_index :datasets, name: OLD_INDEX_NAME, algorithm: :concurrently, if_exists: true
    add_index :datasets, NEW_YEAR_EXPRESSION, name: NEW_INDEX_NAME, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :datasets, name: NEW_INDEX_NAME, algorithm: :concurrently, if_exists: true
    add_index :datasets,
              "(EXTRACT(YEAR FROM COALESCE(published_at, updated_at, created_at))::int)",
              name: OLD_INDEX_NAME,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
