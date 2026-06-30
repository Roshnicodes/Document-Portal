class CreateDownloadRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :download_requests do |t|
      t.references :document, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :otp_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :verified_at
      t.datetime :downloaded_at

      t.timestamps
    end

    add_index :download_requests, %i[document_id user_id created_at]
    add_index :download_requests, :verified_at
  end
end
