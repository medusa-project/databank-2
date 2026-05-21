class CreatorsController < ApplicationController
  before_action :set_dataset
  before_action :set_creator, only: %i[update destroy]

  def create
    @creator = @dataset.creators.build(creator_params)

    if @creator.save
      redirect_to edit_dataset_path(@dataset), notice: "Creator added."
    else
      redirect_to edit_dataset_path(@dataset), alert: @creator.errors.full_messages.to_sentence
    end
  end

  def update
    if @creator.update(creator_params)
      redirect_to edit_dataset_path(@dataset), notice: "Creator updated."
    else
      redirect_to edit_dataset_path(@dataset), alert: @creator.errors.full_messages.to_sentence
    end
  end

  def destroy
    @creator.destroy!
    redirect_to edit_dataset_path(@dataset), notice: "Creator removed."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :update, @dataset
  end

  def set_creator
    @creator = @dataset.creators.find(params[:id])
  end

  def creator_params
    params.require(:creator).permit(:name, :email, :contact, :position)
  end
end
