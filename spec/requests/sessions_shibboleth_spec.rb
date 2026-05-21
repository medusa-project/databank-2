require "rails_helper"

RSpec.describe "Sessions Shibboleth", type: :request do
  it "signs in from proxy headers" do
    post "/auth/shibboleth/callback", headers: {
      "REMOTE_USER" => "netid@example.edu",
      "HTTP_MAIL" => "netid@example.edu",
      "HTTP_DISPLAYNAME" => "Net Id"
    }

    expect(response).to redirect_to(root_path)

    user = User.find_by(provider: "shibboleth", uid: "netid@example.edu")
    expect(user).not_to be_nil
    expect(user.email).to eq("netid@example.edu")
    expect(user.name).to eq("Net Id")
  end

  it "fails when required headers are missing" do
    post "/auth/shibboleth/callback"

    expect(response).to redirect_to(login_path)

    follow_redirect!
    expect(response.body).to include("Authentication failed.")
  end
end
