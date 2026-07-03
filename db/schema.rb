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

ActiveRecord::Schema[8.1].define(version: 2026_07_03_000200) do
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

  create_table "documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "folder_name"
    t.string "folder_path"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "upload_batch_id"
    t.bigint "uploaded_by_id", null: false
    t.index ["folder_name"], name: "index_documents_on_folder_name"
    t.index ["upload_batch_id"], name: "index_documents_on_upload_batch_id"
    t.index ["uploaded_by_id"], name: "index_documents_on_uploaded_by_id"
  end

  create_table "download_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id"
    t.text "download_purpose"
    t.datetime "downloaded_at"
    t.datetime "expires_at", null: false
    t.string "folder_key"
    t.string "folder_name"
    t.string "otp_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "verified_at"
    t.index ["document_id", "user_id", "created_at"], name: "idx_on_document_id_user_id_created_at_2d58031ff7"
    t.index ["document_id"], name: "index_download_requests_on_document_id"
    t.index ["folder_key"], name: "index_download_requests_on_folder_key"
    t.index ["user_id"], name: "index_download_requests_on_user_id"
    t.index ["verified_at"], name: "index_download_requests_on_verified_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "admin_mobile"
    t.datetime "created_at", null: false
    t.string "department"
    t.string "designation"
    t.string "email", null: false
    t.string "employee_code"
    t.string "l1_code"
    t.string "l1_name"
    t.string "l2_code"
    t.string "l2_name"
    t.string "l3_code"
    t.string "l3_name"
    t.string "mobile_number"
    t.string "name", null: false
    t.string "office_name"
    t.string "office_type"
    t.string "password_digest", null: false
    t.string "password_salt", null: false
    t.string "position"
    t.string "role", default: "user", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["employee_code"], name: "index_users_on_employee_code", unique: true
    t.index ["office_name"], name: "index_users_on_office_name"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "documents", "users", column: "uploaded_by_id"
  add_foreign_key "download_requests", "documents"
  add_foreign_key "download_requests", "users"
end
