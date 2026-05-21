class RelatedMaterialsController < ApplicationController
  before_action :set_dataset
  before_action :set_related_material, only: %i[update destroy]

  def create
    @related_material = @dataset.related_materials.build(related_material_params)

    if @related_material.save
      redirect_to edit_dataset_path(@dataset), notice: "Related material added."
    else
      redirect_to edit_dataset_path(@dataset), alert: @related_material.errors.full_messages.to_sentence
    end
  end

  def update
    if @related_material.update(related_material_params)
      redirect_to edit_dataset_path(@dataset), notice: "Related material updated."
    else
      redirect_to edit_dataset_path(@dataset), alert: @related_material.errors.full_messages.to_sentence
    end
  end

  def destroy
    @related_material.destroy!
    redirect_to edit_dataset_path(@dataset), notice: "Related material removed."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :update, @dataset
  end

  def set_related_material
    @related_material = @dataset.related_materials.find(params[:id])
  end

  def related_material_params
    params.require(:related_material).permit(:title, :uri, :relation_type, :position)
  end
end
