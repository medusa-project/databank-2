require "rails_helper"

RSpec.describe "Dataset token endpoints", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  let(:dataset) do
    Dataset.create!(
      title: "Token dataset",
      description: "Dataset for token endpoint tests",
      owner_uid: "owner-token-1",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu"
    )
  end

  it "returns the current token and creates one when missing" do
    sign_in_as(email: dataset.depositor_email, name: "Owner User", role: "depositor")

    get get_current_token_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
    first_token = JSON.parse(response.body).fetch("token")

    get get_current_token_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
    second_token = JSON.parse(response.body).fetch("token")

    expect(second_token).to eq(first_token)
  end

  it "replaces the existing token when requesting a new one" do
    sign_in_as(email: dataset.depositor_email, name: "Owner User", role: "depositor")

    get get_current_token_dataset_path(dataset), as: :json
    old_identifier = JSON.parse(response.body).fetch("token")

    get get_new_token_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
    new_identifier = JSON.parse(response.body).fetch("token")

    expect(new_identifier).not_to eq(old_identifier)
    expect(dataset.reload.token&.identifier).to eq(new_identifier)
    expect(Token.where(dataset_key: dataset.key).count).to eq(1)
  end

  it "blocks users who cannot edit the dataset" do
    sign_in_as(email: "other@example.edu", name: "Other User", role: "depositor")

    get get_current_token_dataset_path(dataset), as: :json

    expect(response).to redirect_to(root_path)
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
