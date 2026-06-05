require "rails_helper"

RSpec.describe "Sessions Shibboleth", type: :request do
  it "signs in with developer callback in test environment" do
    post "/auth/developer/callback", params: {
      name: "Net Id",
      email: "netid@example.edu",
      role: "depositor"
    }

    expect(response).to redirect_to(root_path)

    user = User.find_by(provider: "developer", uid: "netid@example.edu")
    expect(user).not_to be_nil
    expect(user.email).to eq("netid@example.edu")
    expect(user.name).to eq("Net Id")
  end

  it "redirects to root when auth hash is missing" do
    post "/auth/shibboleth/callback"

    expect(response).to redirect_to(root_path)

    follow_redirect!
    expect(response.body).to include("The supplied credentials could not be authenciated.")
  end

  it "does not show no-deposit warning when user has an admin-managed deposit exception" do
    ManagedDepositException.create!(email: "special.depositor@example.edu")

    post "/auth/developer/callback", params: {
      name: "Exception User",
      email: "special.depositor@example.edu",
      role: "no_deposit"
    }

    expect(response).to redirect_to(root_path)

    follow_redirect!
    expect(response.body).not_to include("ACCOUNT NOT ELIGABLE TO DEPOSIT DATA")
  end
end
