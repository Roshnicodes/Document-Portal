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

  def update_profile
    @user.assign_attributes(profile_params)

    return false if @user.errors.any?

    @user.save
  end
end
