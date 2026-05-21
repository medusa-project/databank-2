class ErrorsController < ApplicationController
  skip_before_action :authenticate_user!

  def error404
    render "errors/error404", status: :not_found
  end
end
