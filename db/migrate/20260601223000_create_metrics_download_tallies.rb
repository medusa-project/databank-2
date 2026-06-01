class CreateMetricsDownloadTallies < ActiveRecord::Migration[8.1]
  def change
    create_table :dataset_download_tallies do |t|
      t.string :dataset_key, null: false
      t.string :doi
      t.date :download_date, null: false
      t.integer :tally, null: false, default: 0

      t.timestamps
    end
    add_index :dataset_download_tallies, :dataset_key
    add_index :dataset_download_tallies, [ :dataset_key, :download_date ], unique: true, name: "index_dataset_download_tallies_unique_daily"

    create_table :file_download_tallies do |t|
      t.string :file_web_id, null: false
      t.string :filename
      t.string :dataset_key
      t.string :doi
      t.date :download_date, null: false
      t.integer :tally, null: false, default: 0

      t.timestamps
    end
    add_index :file_download_tallies, :file_web_id
    add_index :file_download_tallies, :dataset_key
    add_index :file_download_tallies, [ :file_web_id, :download_date ], unique: true, name: "index_file_download_tallies_unique_daily"

    create_table :day_file_downloads do |t|
      t.string :ip_address, null: false
      t.string :file_web_id, null: false
      t.string :filename
      t.string :dataset_key, null: false
      t.string :doi
      t.date :download_date, null: false

      t.timestamps
    end
    add_index :day_file_downloads, [ :ip_address, :file_web_id, :download_date ], unique: true, name: "index_day_file_downloads_ip_file_date"
    add_index :day_file_downloads, [ :dataset_key, :download_date ]
  end
end
