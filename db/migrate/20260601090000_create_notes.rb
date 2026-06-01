class CreateNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :notes do |t|
      t.references :dataset, null: false, foreign_key: true
      t.text :body
      t.string :author

      t.timestamps
    end
  end
end
