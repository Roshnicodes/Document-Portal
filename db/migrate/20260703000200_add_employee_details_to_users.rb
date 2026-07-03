class AddEmployeeDetailsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :employee_code, :string
    add_column :users, :mobile_number, :string
    add_column :users, :l1_code, :string
    add_column :users, :l1_name, :string
    add_column :users, :l2_code, :string
    add_column :users, :l2_name, :string
    add_column :users, :l3_code, :string
    add_column :users, :l3_name, :string
    add_column :users, :designation, :string
    add_column :users, :position, :string
    add_column :users, :office_type, :string
    add_column :users, :office_name, :string
    add_column :users, :department, :string

    add_index :users, :employee_code, unique: true
    add_index :users, :office_name
  end
end
