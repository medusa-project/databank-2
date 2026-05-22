# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_22_210000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "contributors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.string "email"
    t.string "family_name"
    t.string "given_name"
    t.string "identifier"
    t.string "identifier_scheme"
    t.string "institution_name"
    t.boolean "is_contact", default: false, null: false
    t.string "name", null: false
    t.integer "position"
    t.string "role"
    t.integer "row_order"
    t.integer "row_position"
    t.integer "type_of"
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_contributors_on_dataset_id"
  end

  create_table "creators", force: :cascade do |t|
    t.boolean "contact", default: false, null: false
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.string "email"
    t.string "family_name"
    t.string "given_name"
    t.string "identifier"
    t.string "identifier_scheme"
    t.string "institution_name"
    t.boolean "is_contact", default: false, null: false
    t.string "name", null: false
    t.integer "position"
    t.integer "row_order"
    t.integer "row_position"
    t.integer "type_of"
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_creators_on_dataset_id"
  end

  create_table "datafiles", force: :cascade do |t|
    t.string "binary_name"
    t.bigint "binary_size"
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.text "description"
    t.string "medusa_id"
    t.integer "row_position"
    t.string "storage_key"
    t.string "storage_root"
    t.datetime "updated_at", null: false
    t.string "web_id"
    t.index ["dataset_id"], name: "index_datafiles_on_dataset_id"
    t.index ["storage_root", "storage_key"], name: "index_datafiles_on_storage_location"
    t.index ["web_id"], name: "index_datafiles_on_web_id", unique: true
  end

  create_table "datasets", force: :cascade do |t|
    t.string "agree"
    t.boolean "complete"
    t.string "corresponding_creator_email"
    t.string "corresponding_creator_name"
    t.datetime "created_at", null: false
    t.string "dataset_version"
    t.string "depositor_email", null: false
    t.string "depositor_name", null: false
    t.text "description"
    t.string "embargo"
    t.string "external_files_link"
    t.text "external_files_note"
    t.string "have_permission"
    t.string "identifier"
    t.boolean "is_import", default: false, null: false
    t.boolean "is_test", default: false, null: false
    t.string "key", null: false
    t.text "keywords"
    t.string "license"
    t.string "medusa_dataset_dir"
    t.datetime "nested_updated_at"
    t.boolean "org_creators", default: false, null: false
    t.string "owner_uid", null: false
    t.integer "publication_state", default: 0, null: false
    t.datetime "published_at"
    t.string "publisher"
    t.date "release_date"
    t.string "removed_private"
    t.string "search"
    t.string "subject"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.text "version_comment"
    t.index ["depositor_email"], name: "index_datasets_on_depositor_email"
    t.index ["identifier"], name: "index_datasets_on_identifier", unique: true, where: "(identifier IS NOT NULL)"
    t.index ["key"], name: "index_datasets_on_key", unique: true
  end

  create_table "external_delivery_attempts", force: :cascade do |t|
    t.integer "attempt", default: 1, null: false
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.jsonb "details", default: {}, null: false
    t.string "error_class"
    t.text "error_message"
    t.string "event_name", null: false
    t.string "idempotency_key"
    t.string "integration", null: false
    t.string "job_id"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id", "integration", "created_at"], name: "index_delivery_attempts_on_dataset_integration_created"
    t.index ["dataset_id", "integration", "event_name", "idempotency_key", "status"], name: "index_delivery_attempts_idempotency_status"
    t.index ["dataset_id"], name: "index_external_delivery_attempts_on_dataset_id"
    t.index ["integration"], name: "index_external_delivery_attempts_on_integration"
    t.index ["status"], name: "index_external_delivery_attempts_on_status"
  end

  create_table "funders", force: :cascade do |t|
    t.string "award_number"
    t.string "code"
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.string "grant"
    t.string "identifier"
    t.string "identifier_scheme"
    t.string "name", null: false
    t.integer "position"
    t.integer "row_position"
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_funders_on_dataset_id"
  end

  create_table "migration_runs", force: :cascade do |t|
    t.string "bundle_path"
    t.string "checksum_path"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "created_count", default: 0, null: false
    t.jsonb "details", default: {}, null: false
    t.integer "expected_count"
    t.integer "failed_count", default: 0, null: false
    t.string "label"
    t.string "manifest_path"
    t.integer "processed_count", default: 0, null: false
    t.string "run_type", null: false
    t.integer "skipped_count", default: 0, null: false
    t.datetime "source_since"
    t.datetime "source_until"
    t.datetime "started_at", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_count", default: 0, null: false
    t.text "validation_error"
    t.integer "would_create_count", default: 0, null: false
    t.integer "would_update_count", default: 0, null: false
    t.index ["run_type"], name: "index_migration_runs_on_run_type"
    t.index ["started_at"], name: "index_migration_runs_on_started_at"
    t.index ["status"], name: "index_migration_runs_on_status"
  end

  create_table "related_materials", force: :cascade do |t|
    t.string "availability"
    t.text "citation"
    t.datetime "created_at", null: false
    t.string "datacite_list"
    t.bigint "dataset_id", null: false
    t.boolean "feature", default: false, null: false
    t.string "link"
    t.string "material_type"
    t.text "note"
    t.integer "position"
    t.string "relation_type"
    t.integer "row_position"
    t.string "selected_type"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uri"
    t.string "uri_type"
    t.index ["dataset_id"], name: "index_related_materials_on_dataset_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.string "provider", default: "developer", null: false
    t.string "role", default: "depositor", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  create_table "version_requests", force: :cascade do |t|
    t.bigint "approved_dataset_id"
    t.text "comment"
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.datetime "requested_at", null: false
    t.string "requester_email", null: false
    t.string "requester_name", null: false
    t.string "requester_uid"
    t.text "review_note"
    t.datetime "reviewed_at"
    t.string "reviewed_by_uid"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["approved_dataset_id"], name: "index_version_requests_on_approved_dataset_id"
    t.index ["dataset_id", "status"], name: "index_version_requests_on_dataset_id_and_status"
    t.index ["dataset_id"], name: "index_version_requests_on_dataset_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "contributors", "datasets"
  add_foreign_key "creators", "datasets"
  add_foreign_key "datafiles", "datasets"
  add_foreign_key "external_delivery_attempts", "datasets"
  add_foreign_key "funders", "datasets"
  add_foreign_key "related_materials", "datasets"
  add_foreign_key "version_requests", "datasets"
  add_foreign_key "version_requests", "datasets", column: "approved_dataset_id"
end
