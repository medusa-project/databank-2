require "rails_helper"

RSpec.describe "Dataset request review", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "allows a dataset owner to request pre-publication review" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create(:dataset, publication_state: :draft, depositor_email: "owner@example.edu", identifier: nil)
    allow(CuratorDirectory).to receive(:review_recipients).and_return([ "curator@example.edu" ])

    expect {
      post request_review_dataset_path(dataset)
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(confirm_review_dataset_path(dataset))
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pre-Publication Review Request Received")
    expect(dataset.reload.identifier).to eq("10.5555/#{dataset.key}")

    mail = ActionMailer::Base.deliveries.last
    expect(mail.subject).to eq("Dataset Consultation Request for #{dataset.key}")
    expect(mail.to).to contain_exactly("curator@example.edu", "owner@example.edu")
    expect(mail.body.encoded).to include("/datasets/#{dataset.key}", "Owner User", "owner@example.edu")
  end

  it "requires sign in for a non-public draft dataset" do
    dataset = create(:dataset, publication_state: :draft)

    post request_review_dataset_path(dataset)

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
