require "rails_helper"

RSpec.describe "Sessions Shibboleth", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:developer] = nil
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "renders the local developer login form in test" do
    get login_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Login")
    expect(response.body).to include("/auth/developer/callback")
  end

  it "redirects login to shibboleth outside test and development" do
    allow(Rails.env).to receive(:test?).and_return(false)
    allow(Rails.env).to receive(:development?).and_return(false)

    get login_path, headers: { "HTTP_REFERER" => "/datasets" }

    expect(response).to redirect_to("/Shibboleth.sso/Login?target=https://#{Databank2::Application.shibboleth_host}/auth/shibboleth/callback")
  end

  it "signs in with developer callback in test environment" do
    sign_in_as(email: "netid@example.edu", name: "Net Id", role: "depositor")

    expect(response).to redirect_to(root_path)

    user = User.find_by(provider: "developer", uid: "netid@example.edu")
    expect(user).not_to be_nil
    expect(user.email).to eq("netid@example.edu")
    expect(user.name).to eq("Net Id")
  end

  it "redirects back to a protected page after successful login" do
    get admin_path

    expect(response).to redirect_to(login_path)

    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect(response).to redirect_to(admin_path)
  end

  it "shows the no-deposit warning when the signed-in user is not allowed to deposit" do
    sign_in_as(email: "undergrad@example.edu", name: "No Deposit User", role: "no_deposit")

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to include("ACCOUNT NOT ELIGABLE TO DEPOSIT DATA")
  end

  it "redirects to root when auth hash is missing" do
    post "/auth/shibboleth/callback"

    expect(response).to redirect_to(root_path)

    follow_redirect!
    expect(response.body).to include("The supplied credentials could not be authenciated.")
  end

  it "does not show no-deposit warning when user has an admin-managed deposit exception" do
    ManagedDepositException.create!(email: "special.depositor@example.edu")

    sign_in_as(email: "special.depositor@example.edu", name: "Exception User", role: "no_deposit")

    expect(response).to redirect_to(root_path)

    follow_redirect!
    expect(response.body).not_to include("ACCOUNT NOT ELIGABLE TO DEPOSIT DATA")
  end

  it "rejects developer callback outside test and development" do
    allow(Rails.env).to receive(:test?).and_return(false)
    allow(Rails.env).to receive(:development?).and_return(false)

    post "/auth/developer/callback", params: {
      name: "Prod Developer",
      email: "prod-dev@example.edu",
      role: "admin"
    }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("The supplied credentials could not be authenciated.")
  end

  it "logs the user out" do
    sign_in_as(email: "logout@example.edu", name: "Logout User", role: "depositor")

    delete logout_path

    expect(response).to redirect_to(root_path)

    get admin_path
    expect(response).to redirect_to(login_path)
  end

  it "switches role to guest" do
    sign_in_as(email: "switch@example.edu", name: "Switch User", role: "depositor")

    post "/role_switch", params: { role: "guest" }

    expect(response).to redirect_to(root_path)
    expect(User.find_by(email: "switch@example.edu").role).to eq("guest")
    follow_redirect!
    expect(response.body).to include("Successfully switched role to guest.")
  end

  it "switches role to no_deposit with the expanded notice text" do
    sign_in_as(email: "switch2@example.edu", name: "Switch User Two", role: "depositor")

    post "/role_switch", params: { role: "no_deposit" }

    expect(response).to redirect_to(root_path)
    expect(User.find_by(email: "switch2@example.edu").role).to eq("no_deposit")
    follow_redirect!
    expect(response.body).to include("Successfully switched role to undergrad, or other authenticated but not authorized agent.")
  end

  it "rejects unknown role switches" do
    sign_in_as(email: "switch3@example.edu", name: "Switch User Three", role: "depositor")

    post "/role_switch", params: { role: "admin" }

    expect(response).to redirect_to(root_path)
    expect(User.find_by(email: "switch3@example.edu").role).to eq("depositor")
    follow_redirect!
    expect(response.body).to include("Unable to switch roles.")
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name,
        nickname: email.split("@").first,
        role: role
      }
    )

    get "/auth/developer/callback"
    expect(response).to have_http_status(:redirect)
  end
end
