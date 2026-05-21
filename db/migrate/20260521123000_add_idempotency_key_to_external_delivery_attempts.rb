class AddIdempotencyKeyToExternalDeliveryAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :external_delivery_attempts, :idempotency_key, :string
    add_index :external_delivery_attempts,
              [ :dataset_id, :integration, :event_name, :idempotency_key, :status ],
              name: "index_delivery_attempts_idempotency_status"
  end
end
