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

  it "does not redirect to an external host from login referer" do
    OmniAuth.config.mock_auth[:developer] = developer_auth(role: "depositor")

    get login_path, headers: { "HTTP_REFERER" => "https://attacker.example/phish" }
    get "/auth/developer/callback"

    expect(response).to redirect_to(root_path)
  end

  it "does not redirect to non-http schemes from login referer" do
    OmniAuth.config.mock_auth[:developer] = developer_auth(role: "depositor")

    get login_path, headers: { "HTTP_REFERER" => "javascript:alert(1)" }
    get "/auth/developer/callback"

    expect(response).to redirect_to(root_path)
  end

  it "rotates the session on login so attacker-controlled session data does not survive" do
    OmniAuth.config.mock_auth[:developer] = developer_auth(role: "depositor")

    stub_const("SessionProbeController", Class.new(ActionController::Base) do
      def index
        head :ok
      end

      def create
        session[:attacker_controlled] = params[:value]
        head :ok
      end

      def show
        render json: {
          attacker_controlled: session[:attacker_controlled],
          user_id: session[:user_id]
        }
      end
    end)

    payload = nil

    with_routing do |set|
      set.draw do
        root to: "session_probe#index"
        get "/auth/:provider/callback", to: "sessions#create"
        post "/auth/:provider/callback", to: "sessions#create"
        post "/session_probe", to: "session_probe#create"
        get "/session_probe", to: "session_probe#show"
      end

      post "/session_probe", params: { value: "seeded-by-attacker" }
      get "/auth/developer/callback"

      expect(response).to have_http_status(:redirect)

      get "/session_probe"
      payload = JSON.parse(response.body)
    end

    expect(payload["attacker_controlled"]).to be_nil
    expect(payload["user_id"]).to eq(User.find_by(email: "person@example.edu")&.id)
  ensure
    Rails.application.reload_routes!
  end

  it "clears attacker-controlled session data and authentication state on logout" do
    OmniAuth.config.mock_auth[:developer] = developer_auth(role: "depositor")

    stub_const("SessionProbeController", Class.new(ActionController::Base) do
      def index
        head :ok
      end

      def create
        session[:attacker_controlled] = params[:value]
        head :ok
      end

      def show
        render json: {
          attacker_controlled: session[:attacker_controlled],
          user_id: session[:user_id]
        }
      end
    end)

    payload = nil

    with_routing do |set|
      set.draw do
        root to: "session_probe#index"
        get "/auth/:provider/callback", to: "sessions#create"
        post "/auth/:provider/callback", to: "sessions#create"
        delete "/logout", to: "sessions#destroy"
        post "/session_probe", to: "session_probe#create"
        get "/session_probe", to: "session_probe#show"
      end

      get "/auth/developer/callback"
      expect(response).to have_http_status(:redirect)

      post "/session_probe", params: { value: "seeded-before-logout" }
      delete "/logout"

      expect(response).to have_http_status(:redirect)

      get "/session_probe"
      payload = JSON.parse(response.body)
    end

    expect(payload["attacker_controlled"]).to be_nil
    expect(payload["user_id"]).to be_nil
  ensure
    Rails.application.reload_routes!
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
