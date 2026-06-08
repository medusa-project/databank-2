require "rails_helper"

RSpec.describe "Errors", type: :request do
  it "renders the 404 page for unmatched html routes" do
    get "/definitely-missing-page"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Page Not Found")
  end
end
