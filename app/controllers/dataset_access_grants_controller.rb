class DatasetAccessGrantsController < ApplicationController
  before_action :set_dataset
  before_action :set_dataset_access_grant, only: :destroy

  def create
    grant_email = dataset_access_grant_params[:email]
    access_level = dataset_access_grant_params[:access_level]

    @dataset_access_grant = @dataset.dataset_access_grants.find_or_initialize_by(email: grant_email)
    @dataset_access_grant.access_level = access_level

    if @dataset_access_grant.save
      notice = @dataset_access_grant.previously_new_record? ? "Dataset access grant added." : "Dataset access grant updated."
      redirect_to edit_dataset_path(@dataset), notice: notice
    else
      redirect_to edit_dataset_path(@dataset), alert: @dataset_access_grant.errors.full_messages.to_sentence
    end
  end

  def destroy
    @dataset_access_grant.destroy!
    redirect_to edit_dataset_path(@dataset), notice: "Dataset access grant removed."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :manage_access, @dataset
  end

  def set_dataset_access_grant
    @dataset_access_grant = @dataset.dataset_access_grants.find(params[:id])
  end

  def dataset_access_grant_params
    params.require(:dataset_access_grant).permit(:email, :access_level)
  end
end
