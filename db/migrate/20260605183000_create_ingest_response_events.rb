class CreateIngestResponseEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ingest_response_events do |t|
      t.references :external_delivery_attempt, foreign_key: true
      t.string :status, null: false
      t.string :correlation_key
      t.string :integration, null: false, default: "ingest"
      t.datetime :received_at, null: false
      t.text :raw_payload
      t.jsonb :payload, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :ingest_response_events, :status
    add_index :ingest_response_events, [ :integration, :status, :received_at ], name: "index_ingest_response_events_on_integration_status_received"
    add_index :ingest_response_events, :correlation_key
  end
end
