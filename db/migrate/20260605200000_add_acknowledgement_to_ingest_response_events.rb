class AddAcknowledgementToIngestResponseEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :ingest_response_events, :acknowledged_at, :datetime
    add_column :ingest_response_events, :acknowledged_by_email, :string
    add_column :ingest_response_events, :acknowledged_note, :text

    add_index :ingest_response_events, :acknowledged_at
  end
end
