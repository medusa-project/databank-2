class AddPublicationYearExpressionIndexToDatasets < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_datasets_on_effective_publication_year".freeze
  YEAR_EXPRESSION = "(EXTRACT(YEAR FROM COALESCE(published_at, updated_at, created_at))::int)".freeze

  def up
    add_index :datasets, YEAR_EXPRESSION, name: INDEX_NAME, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :datasets, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
