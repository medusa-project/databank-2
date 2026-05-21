class CreateExternalDeliveryAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :external_delivery_attempts do |t|
      t.references :dataset, null: false, foreign_key: true
      t.string :integration, null: false
      t.string :event_name, null: false
      t.string :status, null: false
      t.integer :attempt, null: false, default: 1
      t.string :job_id
      t.string :error_class
      t.text :error_message
      t.jsonb :details, null: false, default: {}

      t.timestamps
    end

    add_index :external_delivery_attempts, :integration
    add_index :external_delivery_attempts, :status
    add_index :external_delivery_attempts, [ :dataset_id, :integration, :created_at ], name: "index_delivery_attempts_on_dataset_integration_created"
  end
end
