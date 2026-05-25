module Guide
  class ItemsController < ApplicationController
    before_action :authorize_guide_management!
    before_action :set_guide_item, only: %i[edit update destroy]

    def index
      @title = "Guide Items"
      @guide_items = Guide::Item.includes(:guide_section).ordered
    end

    def new
      @title = "New Guide Item"
      @guide_item = Guide::Item.new(section_id: params[:section_id])
      load_sections
    end

    def edit
      @title = @guide_item.label.present? ? "Edit #{@guide_item.label}" : "Edit Guide Item"
      load_sections
    end

    def create
      @guide_item = Guide::Item.new(guide_item_params)

      if @guide_item.save
        redirect_to guide_items_path, notice: "Item was successfully created."
      else
        @title = "New Guide Item"
        load_sections
        render :new, status: :unprocessable_content
      end
    end

    def update
      if @guide_item.update(guide_item_params)
        redirect_to guide_items_path, notice: "Item was successfully updated."
      else
        @title = @guide_item.label.present? ? "Edit #{@guide_item.label}" : "Edit Guide Item"
        load_sections
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @guide_item.destroy
      redirect_to guide_items_path, notice: "Item was successfully deleted."
    end

    private

    def authorize_guide_management!
      authorize! :manage, Guide::Section
    end

    def set_guide_item
      @guide_item = Guide::Item.find(params[:id])
    end

    def load_sections
      @guide_sections = Guide::Section.ordered
    end

    def guide_item_params
      params.require(:guide_item).permit(:section_id, :anchor, :label, :ordinal, :heading, :public, :body)
    end
  end
end
