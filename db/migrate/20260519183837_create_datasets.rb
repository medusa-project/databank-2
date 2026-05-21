class CreateDatasets < ActiveRecord::Migration[8.1]
  def change
    create_table :datasets do |t|
      t.string  :key,               null: false
      t.string  :title,             null: false
      t.text    :description
      t.string  :owner_uid,         null: false
      t.string  :depositor_name,    null: false
      t.string  :depositor_email,   null: false
      t.integer :publication_state, null: false, default: 0
      t.string  :identifier
      t.datetime :published_at

      t.timestamps
    end
    add_index :datasets, :key, unique: true
    add_index :datasets, :depositor_email
    add_index :datasets, :identifier, unique: true, where: "identifier IS NOT NULL"
  end
end
