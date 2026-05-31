class WelcomeController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :require_admin!, only: %i[admin update_system_message create_managed_curator destroy_managed_curator]
  before_action :load_admin_page_data, only: :admin

  def index
    @featured_researcher = FeaturedResearcher.active.order(Arel.sql("RANDOM()")).first
  end

  def admin; end

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

  def button_examples; end

  private

  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: "You are not authorized to perform this action."
  end

  def admin_message_params
    params.fetch(:admin_page, {}).permit(:system_message)
  end

  def managed_curator_email_param
    params.fetch(:managed_curator, {}).permit(:email)[:email].to_s.strip.downcase
  end

  def load_admin_page_data
    @core_curator_emails = CuratorDirectory.core_emails
    @managed_curators = ManagedCurator.order(:email)
    @system_message_for_form = AppSetting.system_message
  end
end
