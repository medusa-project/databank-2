class ContributorsController < ApplicationController
  before_action :set_dataset
  before_action :set_contributor, only: %i[update destroy]

  def create
    @contributor = @dataset.contributors.build
    assign_contributor_attributes(@contributor)

    if @contributor.save
      redirect_to edit_dataset_path(@dataset), notice: "Contributor added."
    else
      redirect_to edit_dataset_path(@dataset), alert: @contributor.errors.full_messages.to_sentence
    end
  end

  def update
    assign_contributor_attributes(@contributor)

    if @contributor.save
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
    params.require(:contributor)
  end

  def assign_contributor_attributes(contributor)
    contributor.name = contributor_params[:name]
    contributor.family_name = contributor_params[:family_name]
    contributor.given_name = contributor_params[:given_name]
    contributor.institution_name = contributor_params[:institution_name]
    contributor.identifier = contributor_params[:identifier]
    contributor.identifier_scheme = contributor_params[:identifier_scheme]
    contributor.type_of = contributor_params[:type_of]
    contributor.email = contributor_params[:email]
    contributor.role = contributor_params[:role]
    contributor.position = contributor_params[:position]
    contributor.row_position = contributor_params[:row_position]
    contributor.row_order = contributor_params[:row_order]
    contributor.is_contact = contributor_params[:is_contact]
  end
end
