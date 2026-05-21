class PagesController < ApplicationController
  skip_before_action :authenticate_user!

  def deposit; end
  def policies; end
  def guides; end
  def contact; end
end
