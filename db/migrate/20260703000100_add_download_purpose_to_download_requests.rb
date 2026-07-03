class AddDownloadPurposeToDownloadRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :download_requests, :download_purpose, :text
  end
end
