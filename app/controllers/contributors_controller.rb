class ContributorsController < ApplicationController
  before_action :set_dataset
  before_action :set_contributor, only: %i[update destroy]

  def create
    @contributor = @dataset.contributors.build(contributor_params)

    if @contributor.save
      redirect_to edit_dataset_path(@dataset), notice: "Contributor added."
    else
      redirect_to edit_dataset_path(@dataset), alert: @contributor.errors.full_messages.to_sentence
    end
  end

  def update
    if @contributor.update(contributor_params)
      redirect_to edit_dataset_path(@dataset), notice: "Contributor updated."
    else
      redirect_to edit_dataset_path(@dataset), alert: @contributor.errors.full_messages.to_sentence
    end
  end

  def destroy
    @contributor.destroy!
    redirect_to edit_dataset_path(@dataset), notice: "Contributor removed."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :update, @dataset
  end

  def set_contributor
    @contributor = @dataset.contributors.find(params[:id])
  end

  def contributor_params
    params.require(:contributor).permit(
      :name,
      :family_name,
      :given_name,
      :institution_name,
      :identifier,
      :identifier_scheme,
      :type_of,
      :email,
      :role,
      :position,
      :row_position,
      :row_order,
      :is_contact
    )
  end
end
