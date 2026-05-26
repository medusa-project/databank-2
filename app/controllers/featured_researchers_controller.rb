class FeaturedResearchersController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index show]
  before_action :set_featured_researcher, only: %i[show preview edit update destroy]
  before_action :authorize_featured_researcher_management!, only: %i[new create edit update destroy preview]

  def index
    @title = "Researcher Spotlights"
    @featured_researchers = if logged_in? && can?(:manage, FeaturedResearcher)
                              FeaturedResearcher.order(updated_at: :desc)
    else
                              FeaturedResearcher.active.order(Arel.sql("RANDOM()"))
    end
  end

  def show
    @title = @featured_researcher.name.presence || "Researcher Spotlight"
  end

  def preview
    @title = @featured_researcher.name.presence || "Researcher Spotlight Preview"
  end

  def new
    @title = "New Researcher Spotlight"
    @featured_researcher = FeaturedResearcher.new
  end

  def edit
    @title = @featured_researcher.name.present? ? "Edit #{@featured_researcher.name}" : "Edit Researcher Spotlight"
  end

  def create
    @featured_researcher = FeaturedResearcher.new(featured_researcher_params)
    @title = "New Researcher Spotlight"

    if @featured_researcher.save
      redirect_to preview_featured_researcher_path(@featured_researcher), notice: "Researcher spotlight was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @featured_researcher.update(featured_researcher_params)
      redirect_to preview_featured_researcher_path(@featured_researcher), notice: "Researcher spotlight was successfully updated."
    else
      @title = @featured_researcher.name.present? ? "Edit #{@featured_researcher.name}" : "Edit Researcher Spotlight"
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @featured_researcher.destroy
    redirect_to featured_researchers_path, notice: "Researcher spotlight was successfully deleted."
  end

  private

  def set_featured_researcher
    @featured_researcher = FeaturedResearcher.find(params[:id])
  end

  def authorize_featured_researcher_management!
    authorize! :manage, FeaturedResearcher
  end

  def featured_researcher_params
    params.require(:featured_researcher).permit(
      :name,
      :question,
      :dataset_url,
      :article_url,
      :bio,
      :testimonial,
      :photo_url,
      :is_active
    )
  end
end
