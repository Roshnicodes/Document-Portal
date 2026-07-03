class EnforceSingleAdminEmployeeCode < ActiveRecord::Migration[8.1]
  ADMIN_EMPLOYEE_CODE = "397".freeze

  def up
    execute sanitize_sql_array(["UPDATE users SET role = 'user' WHERE role = 'admin' AND employee_code IS DISTINCT FROM ?", ADMIN_EMPLOYEE_CODE])
    execute sanitize_sql_array(["UPDATE users SET role = 'admin' WHERE employee_code = ?", ADMIN_EMPLOYEE_CODE])
  end

  def down
    execute sanitize_sql_array(["UPDATE users SET role = 'user' WHERE employee_code = ?", ADMIN_EMPLOYEE_CODE])
  end

  private

  def sanitize_sql_array(array)
    ActiveRecord::Base.sanitize_sql_array(array)
  end
end
