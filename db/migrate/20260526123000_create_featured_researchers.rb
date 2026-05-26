class CreateFeaturedResearchers < ActiveRecord::Migration[8.1]
  def change
    create_table :featured_researchers do |t|
      t.string :name, null: false
      t.text :question
      t.string :dataset_url
      t.string :article_url
      t.text :bio
      t.text :testimonial
      t.string :photo_url
      t.boolean :is_active, null: false, default: false

      t.timestamps
    end

    add_index :featured_researchers, :is_active
  end
end
