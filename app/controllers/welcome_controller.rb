class WelcomeController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index button_examples]
  before_action :require_admin_or_curator!, only: %i[admin clear_cache update_system_message create_managed_curator destroy_managed_curator create_managed_deposit_exception destroy_managed_deposit_exception]
  before_action :require_curator!, only: :curator_guide
  before_action :load_admin_page_data, only: :admin

  def index
    @featured_researcher = FeaturedResearcher.active.order(Arel.sql("RANDOM()")).first
  end

  def admin; end

  def curator_guide; end

  def clear_cache
    Rails.cache.clear
    redirect_to admin_path, notice: "Rails cache cleared successfully."
  rescue StandardError => e
    redirect_to admin_path, alert: "Rails cache could not be cleared: #{e.message}"
  end

  def update_system_message
    AppSetting.system_message = admin_message_params[:system_message]
    redirect_to admin_path, notice: "System-wide message updated."
  rescue ActiveRecord::RecordInvalid
    load_admin_page_data
    flash.now[:alert] = "System-wide message could not be saved."
    render :admin, status: :unprocessable_entity
  end

  def create_managed_curator
    email = managed_curator_email_param

    if email.blank?
      redirect_to admin_path, alert: "Curator email is required."
      return
    end

    if CuratorDirectory.core_email?(email)
      redirect_to admin_path, notice: "#{email} is already a core curator."
      return
    end

    managed_curator = ManagedCurator.find_or_initialize_by(email: email)

    if managed_curator.persisted?
      redirect_to admin_path, notice: "#{email} is already an admin-managed curator."
    elsif managed_curator.save
      redirect_to admin_path, notice: "Added #{email} as an admin-managed curator."
    else
      redirect_to admin_path, alert: managed_curator.errors.full_messages.to_sentence
    end
  end

  def destroy_managed_curator
    managed_curator = ManagedCurator.find(params[:id])
    managed_curator.destroy!

    redirect_to admin_path, notice: "Removed #{managed_curator.email} from admin-managed curators."
  end

  def create_managed_deposit_exception
    email = managed_deposit_exception_email_param

    if email.blank?
      redirect_to admin_path, alert: "Deposit exception email is required."
      return
    end

    managed_exception = ManagedDepositException.find_or_initialize_by(email: email)

    if managed_exception.persisted?
      redirect_to admin_path, notice: "#{email} is already an admin-managed deposit exception."
    elsif managed_exception.save
      redirect_to admin_path, notice: "Added #{email} as an admin-managed deposit exception."
    else
      redirect_to admin_path, alert: managed_exception.errors.full_messages.to_sentence
    end
  end

  def destroy_managed_deposit_exception
    managed_exception = ManagedDepositException.find(params[:id])
    managed_exception.destroy!

    redirect_to admin_path, notice: "Removed #{managed_exception.email} from admin-managed deposit exceptions."
  end

  def button_examples; end

  private

  def require_admin_or_curator!
    return if current_user&.admin? || current_user&.curator?

    redirect_to root_path, alert: "You are not authorized to perform this action."
  end

  def require_curator!
    return if current_user&.curator?

    redirect_to root_path, alert: "You are not authorized to perform this action."
  end

  def admin_message_params
    params.fetch(:admin_page, {}).permit(:system_message)
  end

  def managed_curator_email_param
    params.fetch(:managed_curator, {}).permit(:email)[:email].to_s.strip.downcase
  end

  def managed_deposit_exception_email_param
    params.fetch(:managed_deposit_exception, {}).permit(:email)[:email].to_s.strip.downcase
  end

  def load_admin_page_data
    @core_curator_emails = CuratorDirectory.core_emails
    @managed_curators = ManagedCurator.order(:email)
    @managed_deposit_exceptions = ManagedDepositException.order(:email)
    @system_message_for_form = AppSetting.system_message
  end
end
