class EnforceUniqueDatasetTokens < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DELETE FROM tokens
      WHERE dataset_key IS NULL
         OR identifier IS NULL
         OR NOT EXISTS (
           SELECT 1 FROM datasets WHERE datasets.key = tokens.dataset_key
         )
    SQL

    execute <<~SQL
      DELETE FROM tokens
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (PARTITION BY dataset_key ORDER BY updated_at DESC, id DESC) AS row_number
          FROM tokens
        ) duplicates
        WHERE duplicates.row_number > 1
      )
    SQL

    execute <<~SQL
      DELETE FROM tokens
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (PARTITION BY identifier ORDER BY updated_at DESC, id DESC) AS row_number
          FROM tokens
        ) duplicates
        WHERE duplicates.row_number > 1
      )
    SQL

    change_column_null :tokens, :dataset_key, false
    change_column_null :tokens, :identifier, false

    remove_index :tokens, :dataset_key
    remove_index :tokens, :identifier
    add_index :tokens, :dataset_key, unique: true
    add_index :tokens, :identifier, unique: true
    add_foreign_key :tokens, :datasets, column: :dataset_key, primary_key: :key
  end

  def down
    remove_foreign_key :tokens, column: :dataset_key
    remove_index :tokens, :dataset_key
    remove_index :tokens, :identifier
    add_index :tokens, :dataset_key
    add_index :tokens, :identifier
    change_column_null :tokens, :dataset_key, true
    change_column_null :tokens, :identifier, true
  end
end
