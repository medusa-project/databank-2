class FundersController < ApplicationController
  before_action :set_dataset
  before_action :set_funder, only: %i[update destroy]

  def create
    @funder = @dataset.funders.build(funder_params)

    if @funder.save
      redirect_to edit_dataset_path(@dataset), notice: "Funder added."
    else
      redirect_to edit_dataset_path(@dataset), alert: @funder.errors.full_messages.to_sentence
    end
  end

  def update
    if @funder.update(funder_params)
      redirect_to edit_dataset_path(@dataset), notice: "Funder updated."
    else
      redirect_to edit_dataset_path(@dataset), alert: @funder.errors.full_messages.to_sentence
    end
  end

  def destroy
    @funder.destroy!
    redirect_to edit_dataset_path(@dataset), notice: "Funder removed."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :update, @dataset
  end

  def set_funder
    @funder = @dataset.funders.find(params[:id])
  end

  def funder_params
    params.require(:funder).permit(:name, :award_number, :identifier, :position)
  end
end
