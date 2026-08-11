class CreateReviewRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :review_requests do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :requester_name, null: false
      t.string :requester_email, null: false
      t.datetime :requested_at, null: false

      t.timestamps
    end
  end
end
