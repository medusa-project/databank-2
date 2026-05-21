class CreateMigrationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_runs do |t|
      t.string :run_type, null: false
      t.string :status, null: false
      t.string :label
      t.string :bundle_path
      t.string :checksum_path
      t.string :manifest_path
      t.datetime :source_since
      t.datetime :source_until
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :would_create_count, null: false, default: 0
      t.integer :would_update_count, null: false, default: 0
      t.integer :processed_count, null: false, default: 0
      t.integer :expected_count
      t.text :validation_error
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end

    add_index :migration_runs, :run_type
    add_index :migration_runs, :status
    add_index :migration_runs, :started_at
  end
end
