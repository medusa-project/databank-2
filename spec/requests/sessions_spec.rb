require "rails_helper"

RSpec.describe "Sessions", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "returns to the public page where login was started" do
    OmniAuth.config.mock_auth[:developer] = developer_auth(role: "depositor")

    get login_path, headers: { "HTTP_REFERER" => datasets_path(q: "climate") }
    get "/auth/developer/callback"

    expect(response).to redirect_to("#{datasets_path}?q=climate")
  end

  it "returns to the auth-gated path after login" do
    OmniAuth.config.mock_auth[:developer] = developer_auth(role: "depositor")

    get new_dataset_path
    expect(response).to redirect_to(login_path)

    get "/auth/developer/callback"

    expect(response).to redirect_to(new_dataset_path)
  end

  def developer_auth(role:)
    OmniAuth::AuthHash.new(
      provider: "developer",
      uid: "person@example.edu",
      info: {
        email: "person@example.edu",
        name: "Person Example",
        nickname: "person@example.edu",
        role: role
      }
    )
  end
end
