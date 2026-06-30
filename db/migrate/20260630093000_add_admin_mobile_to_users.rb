class AddAdminMobileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin_mobile, :string
  end
end
