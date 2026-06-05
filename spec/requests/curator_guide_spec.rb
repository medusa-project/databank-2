require "rails_helper"

RSpec.describe "Curator guide", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "requires login" do
    get curator_guide_path

    expect(response).to redirect_to(login_path)
  end

  it "allows curators to access the guide" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    get curator_guide_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Illinois Data Bank Curator Guide")
    expect(response.body).to include("External Delivery Audit")
  end

  it "allows admins because they are curator-capable in the app" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    get curator_guide_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Illinois Data Bank Curator Guide")
  end

  it "rejects depositors without curator access" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor User", role: "depositor")

    get curator_guide_path

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
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
