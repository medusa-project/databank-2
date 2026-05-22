class CreateVersionRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :version_requests do |t|
      t.references :dataset, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :requester_uid
      t.string :requester_email, null: false
      t.string :requester_name, null: false
      t.text :comment
      t.datetime :requested_at, null: false
      t.datetime :reviewed_at
      t.string :reviewed_by_uid
      t.text :review_note
      t.references :approved_dataset, foreign_key: { to_table: :datasets }

      t.timestamps
    end

    add_index :version_requests, [ :dataset_id, :status ]
  end
end
