class CreateArchiveExtractorTables < ActiveRecord::Migration[8.1]
  def change
    create_table :archive_extract_requests do |t|
      t.references :datafile, null: false, foreign_key: true, index: { unique: true }
      t.datetime :sent_at
      t.datetime :response_at
      t.string :status, null: false, default: "pending"
      t.text :raw_response

      t.timestamps
    end

    add_index :archive_extract_requests, :status

    create_table :archive_extract_responses do |t|
      t.references :archive_extract_request, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false
      t.jsonb :response, null: false, default: {}

      t.timestamps
    end

    add_index :archive_extract_responses, :status

    create_table :archive_extract_errors do |t|
      t.references :archive_extract_response, null: false, foreign_key: true
      t.string :error_type
      t.text :error_report

      t.timestamps
    end

    add_index :archive_extract_errors, :error_type
  end
end
