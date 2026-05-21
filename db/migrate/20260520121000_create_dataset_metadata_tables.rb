class CreateDatasetMetadataTables < ActiveRecord::Migration[8.1]
  def change
    create_table :creators do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.boolean :contact, null: false, default: false
      t.integer :position
      t.timestamps
    end

    create_table :contributors do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :role
      t.integer :position
      t.timestamps
    end

    create_table :funders do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :name, null: false
      t.string :award_number
      t.string :identifier
      t.integer :position
      t.timestamps
    end

    create_table :related_materials do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :title, null: false
      t.string :uri
      t.string :relation_type
      t.integer :position
      t.timestamps
    end
  end
end
