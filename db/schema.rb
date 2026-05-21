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

ActiveRecord::Schema[8.1].define(version: 2026_05_21_123000) do
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
    t.string "name", null: false
    t.integer "position"
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_contributors_on_dataset_id"
  end

  create_table "creators", force: :cascade do |t|
    t.boolean "contact", default: false, null: false
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.string "email"
    t.string "name", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_creators_on_dataset_id"
  end

  create_table "datafiles", force: :cascade do |t|
    t.string "binary_name"
    t.bigint "binary_size"
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.text "description"
    t.datetime "updated_at", null: false
    t.string "web_id"
    t.index ["dataset_id"], name: "index_datafiles_on_dataset_id"
    t.index ["web_id"], name: "index_datafiles_on_web_id", unique: true
  end

  create_table "datasets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "depositor_email", null: false
    t.string "depositor_name", null: false
    t.text "description"
    t.string "identifier"
    t.string "key", null: false
    t.text "keywords"
    t.string "license"
    t.string "owner_uid", null: false
    t.integer "publication_state", default: 0, null: false
    t.datetime "published_at"
    t.string "publisher"
    t.string "subject"
    t.string "title", null: false
    t.datetime "updated_at", null: false
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
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.string "identifier"
    t.string "name", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_funders_on_dataset_id"
  end

  create_table "related_materials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.integer "position"
    t.string "relation_type"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uri"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "contributors", "datasets"
  add_foreign_key "creators", "datasets"
  add_foreign_key "datafiles", "datasets"
  add_foreign_key "external_delivery_attempts", "datasets"
  add_foreign_key "funders", "datasets"
  add_foreign_key "related_materials", "datasets"
end
