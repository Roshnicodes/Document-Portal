class AddFolderTargetToDownloadRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :download_requests, :document_id, true
    add_column :download_requests, :folder_key, :string
    add_column :download_requests, :folder_name, :string

    add_index :download_requests, :folder_key
  end
end
