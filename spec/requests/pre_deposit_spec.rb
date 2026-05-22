require "rails_helper"

RSpec.describe "Pre-deposit considerations", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "requires sign-in" do
    get pre_deposit_datasets_path

    expect(response).to redirect_to(login_path)
    follow_redirect!
    expect(response.body).to include("Please sign in to continue.")
  end

  it "shows pre-deposit considerations for a depositor" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    get pre_deposit_datasets_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pre-Deposit Considerations")
    expect(response.body).to include("Files larger than 50 GB require special handling")
    expect(response.body).to include("Select a license for your dataset")
    expect(response.body).to include("Continue")
    expect(response.body).to include(new_dataset_path)
  end

  it "shows the deposit agreement step after pre-deposit" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    get new_dataset_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Deposit Agreement")
    expect(response.body).to include("Required Responses")
  end

  it "creates a draft dataset from valid deposit agreement responses and opens edit form" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      agreement_submission: "true",
      dataset: {
        have_permission: "yes",
        removed_private: "yes",
        agree: "yes"
      }
    }

    dataset = Dataset.order(:created_at).last

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(dataset.have_permission).to eq("yes")
    expect(dataset.removed_private).to eq("yes")
    expect(dataset.agree).to eq("yes")
  end

  it "rejects invalid deposit agreement responses" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    expect do
      post datasets_path, params: {
        agreement_submission: "true",
        dataset: {
          have_permission: "no",
          removed_private: "no",
          agree: "no"
        }
      }
    end.not_to change(Dataset, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be Yes to continue")
    expect(response.body).to include("must be Yes or Not applicable to continue")
  end

  it "redirects /deposit to the pre-deposit workflow route" do
    get deposit_path

    expect(response).to redirect_to(pre_deposit_datasets_path)
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
