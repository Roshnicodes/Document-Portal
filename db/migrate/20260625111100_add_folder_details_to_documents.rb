class AddFolderDetailsToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :folder_name, :string
    add_column :documents, :folder_path, :string
    add_column :documents, :upload_batch_id, :string

    add_index :documents, :folder_name
    add_index :documents, :upload_batch_id
  end
end
