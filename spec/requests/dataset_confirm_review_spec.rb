require "rails_helper"

RSpec.describe "Dataset confirm review", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "shows the confirmation page to a dataset owner" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create(:dataset, depositor_email: "owner@example.edu", publication_state: :draft)

    get confirm_review_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pre-Publication Review Request Received")
  end

  it "requires sign in for a non-public draft dataset" do
    dataset = create(:dataset, publication_state: :draft)

    get confirm_review_dataset_path(dataset)

    expect(response).to redirect_to(login_path)
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name
      },
      extra: {
        raw_info: {
          role: role
        }
      }
    )

    get "/auth/developer/callback"
    follow_redirect! if response.redirect?
  end
end
