module Guide
  class SubitemsController < ApplicationController
    before_action :authorize_guide_management!
    before_action :set_guide_subitem, only: %i[edit update destroy]
    before_action :set_guide_item_context, only: %i[index new]

    def index
      @title = @guide_item ? "Guide Subitems - #{@guide_item.label}" : "Guide Subitems"
      @guide_items = Guide::Item.includes(:guide_section).ordered unless @guide_item
      @guide_subitems = if @guide_item
        Guide::Subitem.includes(guide_item: :guide_section).where(item_id: @guide_item.id).ordered
      else
        Guide::Subitem.none
      end
    end

    def new
      @title = @guide_item ? "New Guide Subitem - #{@guide_item.label}" : "New Guide Subitem"
      @guide_subitem = Guide::Subitem.new(item_id: @guide_item&.id)
      @cancel_path = @guide_item ? guide_subitems_path(item_id: @guide_item.id) : guide_items_path
      load_items
    end

    def edit
      @title = @guide_subitem.label.present? ? "Edit #{@guide_subitem.label}" : "Edit Guide Subitem"
      @guide_item = @guide_subitem.guide_item
      @cancel_path = @guide_item ? guide_subitems_path(item_id: @guide_item.id) : guide_items_path
      load_items
    end

    def create
      @guide_subitem = Guide::Subitem.new(guide_subitem_params)

      if @guide_subitem.save
        redirect_to guide_subitems_path(item_id: @guide_subitem.item_id), notice: "Subitem was successfully created."
      else
        @title = "New Guide Subitem"
        @guide_item = Guide::Item.find_by(id: @guide_subitem.item_id)
        @cancel_path = @guide_item ? guide_subitems_path(item_id: @guide_item.id) : guide_items_path
        load_items
        render :new, status: :unprocessable_content
      end
    end

    def update
      if @guide_subitem.update(guide_subitem_params)
        redirect_to guide_subitems_path(item_id: @guide_subitem.item_id), notice: "Subitem was successfully updated."
      else
        @title = @guide_subitem.label.present? ? "Edit #{@guide_subitem.label}" : "Edit Guide Subitem"
        @guide_item = Guide::Item.find_by(id: @guide_subitem.item_id)
        @cancel_path = @guide_item ? guide_subitems_path(item_id: @guide_item.id) : guide_items_path
        load_items
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      item_id = @guide_subitem.item_id
      @guide_subitem.destroy
      redirect_to guide_subitems_path(item_id: item_id), notice: "Subitem was successfully deleted."
    end

    private

    def authorize_guide_management!
      authorize! :manage, Guide::Section
    end

    def set_guide_subitem
      @guide_subitem = Guide::Subitem.find(params[:id])
    end

    def set_guide_item_context
      @guide_item = Guide::Item.includes(:guide_section).find_by(id: params[:item_id]) if params[:item_id].present?
    end

    def load_items
      @guide_items = Guide::Item.includes(:guide_section).ordered
    end

    def guide_subitem_params
      params.require(:guide_subitem).permit(:item_id, :anchor, :label, :ordinal, :heading, :public, :body)
    end
  end
end
