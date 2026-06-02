class CreateCuratorReports < ActiveRecord::Migration[8.1]
  def change
    create_table :curator_reports do |t|
      t.string :requestor_name, null: false
      t.string :requestor_email, null: false
      t.string :report_type, null: false
      t.string :storage_root
      t.string :storage_key
      t.text :notes

      t.timestamps
    end

    add_index :curator_reports, :report_type
    add_index :curator_reports, :created_at
  end
end
