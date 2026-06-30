class ProfilesController < ApplicationController
  before_action :require_login

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if update_profile
      redirect_to edit_profile_path, notice: "Profile updated successfully."
    else
      flash.now[:alert] = "Please check the highlighted fields."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    permitted_params = params.require(:user).permit(:admin_mobile)
    return permitted_params if admin_user?

    permitted_params.except(:admin_mobile)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end

  def update_profile
    @user.assign_attributes(profile_params)
    validate_password_change

    return false if @user.errors.any?

    assign_new_password
    @user.save
  end

  def assign_new_password
    return if password_params[:password].blank?

    @user.password = password_params[:password]
  end

  def validate_password_change
    return if password_params[:password].blank? && password_params[:password_confirmation].blank? && password_params[:current_password].blank?

    @user.errors.add(:current_password, "is required") if password_params[:current_password].blank?
    @user.errors.add(:current_password, "is incorrect") unless @user.authenticate(password_params[:current_password])
    @user.errors.add(:password, "is required") if password_params[:password].blank?
    @user.errors.add(:password_confirmation, "does not match") if password_params[:password] != password_params[:password_confirmation]
  end
end
