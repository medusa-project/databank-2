require "rails_helper"

RSpec.describe "Dataset edit workflow actions", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  let(:dataset) do
    Dataset.create!(
      title: "Workflow dataset",
      description: "Dataset for edit workflow tests",
      owner_uid: "owner-workflow-1",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu"
    )
  end

  it "redirects to index when save and exit is requested" do
    sign_in_as(email: dataset.depositor_email, name: "Owner User", role: "depositor")

    patch dataset_path(dataset), params: {
      dataset: { title: "Workflow dataset updated" },
      save_and_exit: "true"
    }

    expect(response).to redirect_to(datasets_path)
    follow_redirect!
    expect(response.body).to include("Dataset updated and saved.")
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name,
        nickname: email,
        role: role
      }
    )

    get "/auth/developer/callback"
    expect(response).to have_http_status(:redirect)
  end
end
