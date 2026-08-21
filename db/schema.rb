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

ActiveRecord::Schema[8.1].define(version: 2026_08_18_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

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

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "archive_extract_errors", force: :cascade do |t|
    t.bigint "archive_extract_response_id", null: false
    t.datetime "created_at", null: false
    t.text "error_report"
    t.string "error_type"
    t.datetime "updated_at", null: false
    t.index ["archive_extract_response_id"], name: "index_archive_extract_errors_on_archive_extract_response_id"
    t.index ["error_type"], name: "index_archive_extract_errors_on_error_type"
  end

  create_table "archive_extract_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "datafile_id", null: false
    t.text "raw_response"
    t.datetime "response_at"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["datafile_id"], name: "index_archive_extract_requests_on_datafile_id", unique: true
    t.index ["status"], name: "index_archive_extract_requests_on_status"
  end

  create_table "archive_extract_responses", force: :cascade do |t|
    t.bigint "archive_extract_request_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "response", default: {}, null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["archive_extract_request_id"], name: "index_archive_extract_responses_on_archive_extract_request_id", unique: true
    t.index ["status"], name: "index_archive_extract_responses_on_status"
  end

  create_table "audits", force: :cascade do |t|
    t.string "action"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "auditable_id"
    t.string "auditable_type"
    t.jsonb "audited_changes"
    t.string "comment"
    t.datetime "created_at"
    t.string "remote_address"
    t.string "request_uuid"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.integer "version", default: 0
    t.index ["associated_id", "associated_type"], name: "associated_index"
    t.index ["auditable_id", "auditable_type"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
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
    t.index ["dataset_id", "email"], name: "index_creators_on_dataset_id_and_email"
    t.index ["dataset_id"], name: "index_creators_on_dataset_id"
  end

  create_table "curator_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.string "report_type", null: false
    t.string "requestor_email", null: false
    t.string "requestor_name", null: false
    t.string "storage_key"
    t.string "storage_root"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_curator_reports_on_created_at"
    t.index ["report_type"], name: "index_curator_reports_on_report_type"
  end

  create_table "datafiles", force: :cascade do |t|
    t.string "binary_name"
    t.bigint "binary_size"
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.text "description"
    t.string "medusa_id"
    t.text "peek_content"
    t.string "peek_type"
    t.integer "row_position"
    t.string "storage_key"
    t.string "storage_root"
    t.datetime "updated_at", null: false
    t.string "web_id"
    t.index ["dataset_id"], name: "index_datafiles_on_dataset_id"
    t.index ["peek_type"], name: "index_datafiles_on_peek_type"
    t.index ["storage_root", "storage_key"], name: "index_datafiles_on_storage_location"
    t.index ["web_id"], name: "index_datafiles_on_web_id", unique: true
  end

  create_table "dataset_access_grants", force: :cascade do |t|
    t.integer "access_level", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id", "email"], name: "index_dataset_access_grants_on_dataset_id_and_email", unique: true
    t.index ["dataset_id"], name: "index_dataset_access_grants_on_dataset_id"
    t.index ["email", "access_level"], name: "index_dataset_access_grants_on_email_and_access_level"
  end

  create_table "dataset_download_tallies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dataset_key", null: false
    t.string "doi"
    t.date "download_date", null: false
    t.integer "tally", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_key", "download_date"], name: "index_dataset_download_tallies_unique_daily", unique: true
    t.index ["dataset_key"], name: "index_dataset_download_tallies_on_dataset_key"
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
    t.string "hold_state"
    t.string "identifier"
    t.boolean "is_import", default: false, null: false
    t.boolean "is_test", default: false, null: false
    t.string "key", null: false
    t.text "keywords"
    t.string "legacy_publication_state"
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
    t.boolean "suppress_changelog", default: false, null: false
    t.string "title", null: false
    t.date "tombstone_date"
    t.datetime "updated_at", null: false
    t.text "version_comment"
    t.index "((date_part('year'::text, release_date))::integer)", name: "index_datasets_on_release_year"
    t.index ["depositor_email"], name: "index_datasets_on_depositor_email"
    t.index ["hold_state"], name: "index_datasets_on_hold_state"
    t.index ["identifier"], name: "index_datasets_on_identifier", unique: true, where: "(identifier IS NOT NULL)"
    t.index ["key"], name: "index_datasets_on_key", unique: true
    t.index ["legacy_publication_state"], name: "index_datasets_on_legacy_publication_state"
    t.index ["publication_state", "hold_state", "embargo", "release_date"], name: "index_datasets_on_visibility_filter_columns"
    t.index ["tombstone_date"], name: "index_datasets_on_tombstone_date"
  end

  create_table "day_file_downloads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dataset_key", null: false
    t.string "doi"
    t.date "download_date", null: false
    t.string "file_web_id", null: false
    t.string "filename"
    t.string "ip_address", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_key", "download_date"], name: "index_day_file_downloads_on_dataset_key_and_download_date"
    t.index ["ip_address", "file_web_id", "download_date"], name: "index_day_file_downloads_ip_file_date", unique: true
  end

  create_table "external_delivery_attempts", force: :cascade do |t|
    t.integer "attempt", default: 1, null: false
    t.string "correlation_key"
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.jsonb "details", default: {}, null: false
    t.string "error_class"
    t.text "error_message"
    t.string "event_name", null: false
    t.string "idempotency_key"
    t.string "integration", null: false
    t.string "job_id"
    t.jsonb "response_payload", default: {}, null: false
    t.datetime "response_received_at"
    t.string "response_staging_key"
    t.string "response_status"
    t.string "response_target_key"
    t.string "response_uuid"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id", "integration", "created_at"], name: "index_delivery_attempts_on_dataset_integration_created"
    t.index ["dataset_id", "integration", "event_name", "idempotency_key", "status"], name: "index_delivery_attempts_idempotency_status"
    t.index ["dataset_id"], name: "index_external_delivery_attempts_on_dataset_id"
    t.index ["integration", "correlation_key"], name: "index_delivery_attempts_on_integration_correlation"
    t.index ["integration", "response_status", "created_at"], name: "index_delivery_attempts_on_integration_response_status_created"
    t.index ["integration"], name: "index_external_delivery_attempts_on_integration"
    t.index ["status"], name: "index_external_delivery_attempts_on_status"
  end

  create_table "featured_researchers", force: :cascade do |t|
    t.string "article_url"
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "dataset_url"
    t.boolean "is_active", default: false, null: false
    t.string "name", null: false
    t.string "photo_url"
    t.text "question"
    t.text "testimonial"
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_featured_researchers_on_is_active"
  end

  create_table "file_download_tallies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dataset_key"
    t.string "doi"
    t.date "download_date", null: false
    t.string "file_web_id", null: false
    t.string "filename"
    t.integer "tally", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_key"], name: "index_file_download_tallies_on_dataset_key"
    t.index ["file_web_id", "download_date"], name: "index_file_download_tallies_unique_daily", unique: true
    t.index ["file_web_id"], name: "index_file_download_tallies_on_file_web_id"
  end

  create_table "funders", force: :cascade do |t|
    t.string "award_number"
    t.string "code", default: "other", null: false
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

  create_table "guide_items", force: :cascade do |t|
    t.string "anchor"
    t.datetime "created_at", null: false
    t.string "heading"
    t.string "label"
    t.integer "ordinal"
    t.boolean "public", default: false, null: false
    t.bigint "section_id"
    t.datetime "updated_at", null: false
    t.index ["anchor"], name: "index_guide_items_on_anchor"
    t.index ["section_id"], name: "index_guide_items_on_section_id"
  end

  create_table "guide_sections", force: :cascade do |t|
    t.string "anchor"
    t.datetime "created_at", null: false
    t.string "heading"
    t.string "label"
    t.integer "ordinal"
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["anchor"], name: "index_guide_sections_on_anchor"
  end

  create_table "guide_subitems", force: :cascade do |t|
    t.string "anchor"
    t.datetime "created_at", null: false
    t.string "heading"
    t.bigint "item_id"
    t.string "label"
    t.integer "ordinal"
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["anchor"], name: "index_guide_subitems_on_anchor"
    t.index ["item_id"], name: "index_guide_subitems_on_item_id"
  end

  create_table "ingest_response_events", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.string "acknowledged_by_email"
    t.text "acknowledged_note"
    t.string "correlation_key"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "external_delivery_attempt_id"
    t.string "integration", default: "ingest", null: false
    t.jsonb "payload", default: {}, null: false
    t.text "raw_payload"
    t.datetime "received_at", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged_at"], name: "index_ingest_response_events_on_acknowledged_at"
    t.index ["correlation_key"], name: "index_ingest_response_events_on_correlation_key"
    t.index ["external_delivery_attempt_id"], name: "index_ingest_response_events_on_external_delivery_attempt_id"
    t.index ["integration", "status", "received_at"], name: "index_ingest_response_events_on_integration_status_received"
    t.index ["status"], name: "index_ingest_response_events_on_status"
  end

  create_table "managed_curators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_managed_curators_on_email", unique: true
  end

  create_table "managed_deposit_exceptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_managed_deposit_exceptions_on_email", unique: true
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

  create_table "nested_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "datafile_id", null: false
    t.boolean "is_directory", default: false
    t.string "item_name", null: false
    t.text "item_path"
    t.string "media_type"
    t.bigint "parent_id"
    t.bigint "size"
    t.datetime "updated_at", null: false
    t.index ["datafile_id", "item_name"], name: "index_nested_items_on_datafile_id_and_item_name"
    t.index ["datafile_id"], name: "index_nested_items_on_datafile_id"
    t.index ["parent_id"], name: "index_nested_items_on_parent_id"
  end

  create_table "notes", force: :cascade do |t|
    t.string "author"
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_notes_on_dataset_id"
  end

  create_table "related_material_relationships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 1, null: false
    t.bigint "related_material_id", null: false
    t.string "relation_type", null: false
    t.datetime "updated_at", null: false
    t.index ["related_material_id", "relation_type"], name: "idx_related_material_relationships_unique_relation", unique: true
    t.index ["related_material_id"], name: "index_related_material_relationships_on_related_material_id"
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

  create_table "review_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dataset_id", null: false
    t.datetime "requested_at", null: false
    t.string "requester_email", null: false
    t.string "requester_name", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_review_requests_on_dataset_id"
  end

  create_table "tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dataset_key", null: false
    t.datetime "expires"
    t.string "identifier", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_key"], name: "index_tokens_on_dataset_key", unique: true
    t.index ["identifier"], name: "index_tokens_on_identifier", unique: true
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
  add_foreign_key "archive_extract_errors", "archive_extract_responses"
  add_foreign_key "archive_extract_requests", "datafiles"
  add_foreign_key "archive_extract_responses", "archive_extract_requests"
  add_foreign_key "contributors", "datasets"
  add_foreign_key "creators", "datasets"
  add_foreign_key "datafiles", "datasets"
  add_foreign_key "dataset_access_grants", "datasets"
  add_foreign_key "external_delivery_attempts", "datasets"
  add_foreign_key "funders", "datasets"
  add_foreign_key "guide_items", "guide_sections", column: "section_id"
  add_foreign_key "guide_subitems", "guide_items", column: "item_id"
  add_foreign_key "ingest_response_events", "external_delivery_attempts"
  add_foreign_key "nested_items", "datafiles"
  add_foreign_key "nested_items", "nested_items", column: "parent_id"
  add_foreign_key "notes", "datasets"
  add_foreign_key "related_material_relationships", "related_materials"
  add_foreign_key "related_materials", "datasets"
  add_foreign_key "review_requests", "datasets"
  add_foreign_key "tokens", "datasets", column: "dataset_key", primary_key: "key"
  add_foreign_key "version_requests", "datasets"
  add_foreign_key "version_requests", "datasets", column: "approved_dataset_id"
end
