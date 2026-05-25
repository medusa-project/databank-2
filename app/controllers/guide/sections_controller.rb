module Guide
  class SectionsController < ApplicationController
    before_action :authorize_guide_management!
    before_action :set_guide_section, only: %i[edit update destroy]

    def index
      @title = "Guide Sections"
      @guide_sections = Guide::Section.ordered
    end

    def new
      @title = "New Guide Section"
      @guide_section = Guide::Section.new
    end

    def edit
      @title = @guide_section.label.present? ? "Edit #{@guide_section.label}" : "Edit Guide Section"
    end

    def create
      @guide_section = Guide::Section.new(guide_section_params)

      if @guide_section.save
        redirect_to guide_sections_path, notice: "Section was successfully created."
      else
        @title = "New Guide Section"
        render :new, status: :unprocessable_content
      end
    end

    def update
      if @guide_section.update(guide_section_params)
        redirect_to guide_sections_path, notice: "Section was successfully updated."
      else
        @title = @guide_section.label.present? ? "Edit #{@guide_section.label}" : "Edit Guide Section"
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @guide_section.destroy
      redirect_to guide_sections_path, notice: "Section was successfully deleted."
    end

    private

    def authorize_guide_management!
      authorize! :manage, Guide::Section
    end

    def set_guide_section
      @guide_section = Guide::Section.find(params[:id])
    end

    def guide_section_params
      params.require(:guide_section).permit(:anchor, :label, :ordinal, :heading, :public, :body)
    end
  end
end
