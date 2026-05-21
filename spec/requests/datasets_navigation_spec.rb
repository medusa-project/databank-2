require "rails_helper"

RSpec.describe "Datasets navigation", type: :request do
  it "includes primary header navigation links" do
    get datasets_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<il-header-nav")
    expect(response.body).to include("Deposit Dataset")
    expect(response.body).to include("Find Data")
    expect(response.body).to include("Policies")
    expect(response.body).to include("Guides")
    expect(response.body).to include("Contact Us")
  end
end
