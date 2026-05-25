module Guide
  class ItemsController < ApplicationController
    before_action :authorize_guide_management!
    before_action :set_guide_item, only: %i[edit update destroy]
    before_action :set_guide_section_context, only: %i[index new]

    def index
      @title = @guide_section ? "Guide Items - #{@guide_section.label}" : "Guide Items"
      @guide_sections = Guide::Section.ordered unless @guide_section
      @guide_items = if @guide_section
        Guide::Item.includes(:guide_section).where(section_id: @guide_section.id).ordered
      else
        Guide::Item.none
      end
    end

    def new
      @title = @guide_section ? "New Guide Item - #{@guide_section.label}" : "New Guide Item"
      @guide_item = Guide::Item.new(section_id: @guide_section&.id)
      @cancel_path = @guide_section ? guide_items_path(section_id: @guide_section.id) : guide_sections_path
      load_sections
    end

    def edit
      @title = @guide_item.label.present? ? "Edit #{@guide_item.label}" : "Edit Guide Item"
      @guide_section = @guide_item.guide_section
      @cancel_path = @guide_section ? guide_items_path(section_id: @guide_section.id) : guide_sections_path
      load_sections
    end

    def create
      @guide_item = Guide::Item.new(guide_item_params)

      if @guide_item.save
        redirect_to guide_items_path(section_id: @guide_item.section_id), notice: "Item was successfully created."
      else
        @title = "New Guide Item"
        @guide_section = Guide::Section.find_by(id: @guide_item.section_id)
        @cancel_path = @guide_section ? guide_items_path(section_id: @guide_section.id) : guide_sections_path
        load_sections
        render :new, status: :unprocessable_content
      end
    end

    def update
      if @guide_item.update(guide_item_params)
        redirect_to guide_items_path(section_id: @guide_item.section_id), notice: "Item was successfully updated."
      else
        @title = @guide_item.label.present? ? "Edit #{@guide_item.label}" : "Edit Guide Item"
        @guide_section = Guide::Section.find_by(id: @guide_item.section_id)
        @cancel_path = @guide_section ? guide_items_path(section_id: @guide_section.id) : guide_sections_path
        load_sections
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      section_id = @guide_item.section_id
      @guide_item.destroy
      redirect_to guide_items_path(section_id: section_id), notice: "Item was successfully deleted."
    end

    private

    def authorize_guide_management!
      authorize! :manage, Guide::Section
    end

    def set_guide_item
      @guide_item = Guide::Item.find(params[:id])
    end

    def set_guide_section_context
      @guide_section = Guide::Section.find_by(id: params[:section_id]) if params[:section_id].present?
    end

    def load_sections
      @guide_sections = Guide::Section.ordered
    end

    def guide_item_params
      params.require(:guide_item).permit(:section_id, :anchor, :label, :ordinal, :heading, :public, :body)
    end
  end
end
