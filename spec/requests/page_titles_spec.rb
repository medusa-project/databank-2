require "rails_helper"

RSpec.describe "Page titles", type: :request do
  it "renders the shared page-title component for titled pages" do
    get datasets_path

    expect(response).to have_http_status(:ok)
    expect(response.body.scan('<div class="idb-page-title">').size).to eq(1)
    expect(response.body).to include("<h1>Dataset Search</h1>")
  end

  it "allows views to opt out of the shared page-title component" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('<div class="idb-page-title">')
    expect(response.body).to include("welcome-title")
  end

  it "renders the shared page-title component for static content pages" do
    get policies_path

    expect(response).to have_http_status(:ok)
    expect(response.body.scan('<div class="idb-page-title">').size).to eq(1)
    expect(response.body).to include("<h1>Policies</h1>")
  end
end
