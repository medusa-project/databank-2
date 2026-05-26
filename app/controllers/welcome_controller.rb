class WelcomeController < ApplicationController
  skip_before_action :authenticate_user!

  def index
    @featured_researcher = FeaturedResearcher.active.order(Arel.sql("RANDOM()")).first
  end

  def button_examples; end
end
