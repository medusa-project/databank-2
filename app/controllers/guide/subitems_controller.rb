module Guide
  class SubitemsController < ApplicationController
    before_action :authorize_guide_management!
    before_action :set_guide_subitem, only: %i[edit update destroy]

    def index
      @title = "Guide Subitems"
      @guide_subitems = Guide::Subitem.includes(guide_item: :guide_section).ordered
    end

    def new
      @title = "New Guide Subitem"
      @guide_subitem = Guide::Subitem.new(item_id: params[:item_id])
      load_items
    end

    def edit
      @title = @guide_subitem.label.present? ? "Edit #{@guide_subitem.label}" : "Edit Guide Subitem"
      load_items
    end

    def create
      @guide_subitem = Guide::Subitem.new(guide_subitem_params)

      if @guide_subitem.save
        redirect_to guide_subitems_path, notice: "Subitem was successfully created."
      else
        @title = "New Guide Subitem"
        load_items
        render :new, status: :unprocessable_content
      end
    end

    def update
      if @guide_subitem.update(guide_subitem_params)
        redirect_to guide_subitems_path, notice: "Subitem was successfully updated."
      else
        @title = @guide_subitem.label.present? ? "Edit #{@guide_subitem.label}" : "Edit Guide Subitem"
        load_items
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @guide_subitem.destroy
      redirect_to guide_subitems_path, notice: "Subitem was successfully deleted."
    end

    private

    def authorize_guide_management!
      authorize! :manage, Guide::Section
    end

    def set_guide_subitem
      @guide_subitem = Guide::Subitem.find(params[:id])
    end

    def load_items
      @guide_items = Guide::Item.includes(:guide_section).ordered
    end

    def guide_subitem_params
      params.require(:guide_subitem).permit(:item_id, :anchor, :label, :ordinal, :heading, :public, :body)
    end
  end
end
