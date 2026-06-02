class CreateTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :tokens do |t|
      t.string :dataset_key
      t.string :identifier
      t.datetime :expires

      t.timestamps
    end

    add_index :tokens, :dataset_key
    add_index :tokens, :identifier
  end
end
