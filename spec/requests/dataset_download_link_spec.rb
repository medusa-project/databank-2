require "rails_helper"

RSpec.describe "Dataset download link", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "requires sign in for a non-public draft dataset" do
    dataset = create(:dataset, publication_state: :draft)
    datafile = create(:datafile, dataset: dataset)

    get download_link_dataset_path(dataset), params: { web_ids: datafile.web_id }

    expect(response).to redirect_to(login_path)
  end

  it "handles missing web_ids parameter for public dataset" do
    dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_NONE)

    get download_link_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload["status"]).to eq("error")
    expect(payload["error"]).to include("no web_ids")
  end

  it "requires valid web_ids parameter" do
    dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_NONE, identifier: "10.5555/TEST")
    create(:datafile, dataset: dataset)

    # Send empty web_ids
    get download_link_dataset_path(dataset), params: { web_ids: "" }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload["status"]).to eq("error")
  end
end
