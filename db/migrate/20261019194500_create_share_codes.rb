class CreateShareCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :share_codes do |t|
      t.string :code, null: false
      t.references :dataset, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    add_index :share_codes, :code, unique: true
  end
end
