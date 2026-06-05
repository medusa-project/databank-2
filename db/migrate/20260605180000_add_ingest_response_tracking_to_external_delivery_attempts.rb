class AddIngestResponseTrackingToExternalDeliveryAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :external_delivery_attempts, :correlation_key, :string
    add_column :external_delivery_attempts, :response_status, :string
    add_column :external_delivery_attempts, :response_received_at, :datetime
    add_column :external_delivery_attempts, :response_uuid, :string
    add_column :external_delivery_attempts, :response_staging_key, :string
    add_column :external_delivery_attempts, :response_target_key, :string
    add_column :external_delivery_attempts, :response_payload, :jsonb, null: false, default: {}

    add_index :external_delivery_attempts,
              [ :integration, :correlation_key ],
              name: "index_delivery_attempts_on_integration_correlation"

    add_index :external_delivery_attempts,
              [ :integration, :response_status, :created_at ],
              name: "index_delivery_attempts_on_integration_response_status_created"
  end
end
