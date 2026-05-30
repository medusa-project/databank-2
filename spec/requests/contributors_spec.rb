require "rails_helper"

RSpec.describe "Contributors", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
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

  def create_owned_draft_dataset
    Dataset.create!(
      title: "Contributor Test Dataset",
      description: "desc",
      keywords: "k",
      subject: "s",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-uid",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :draft
    )
  end

  it "creates a contributor for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_contributors_path(dataset), params: {
      contributor: {
        given_name: "Taylor",
        family_name: "Researcher",
        email: "taylor@example.edu",
        role: "Data Curator",
        row_position: 1
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(dataset.contributors.count).to eq(1)

    contributor = dataset.contributors.first
    expect(contributor.name).to eq("Taylor Researcher")
    expect(contributor.role).to eq("Data Curator")
    expect(contributor.position).to eq(1)
  end

  it "rejects invalid contributor create and returns an alert" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_contributors_path(dataset), params: {
      contributor: {
        given_name: "",
        family_name: "",
        institution_name: "",
        name: "",
        role: "Data Curator"
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:alert]).to include("Contributor must have either an institution name")
    expect(dataset.contributors.count).to eq(0)
  end

  it "updates an existing contributor for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    contributor = dataset.contributors.create!(name: "Old Name", role: "Analyst", row_position: 1)

    patch dataset_contributor_path(dataset, contributor), params: {
      contributor: {
        name: "New Name",
        role: "Data Curator",
        row_position: 2
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))

    contributor.reload
    expect(contributor.name).to eq("New Name")
    expect(contributor.role).to eq("Data Curator")
    expect(contributor.position).to eq(2)
  end

  it "destroys an existing contributor for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    contributor = dataset.contributors.create!(name: "Delete Me", role: "Analyst", row_position: 1)

    expect {
      delete dataset_contributor_path(dataset, contributor)
    }.to change(Contributor, :count).by(-1)

    expect(response).to redirect_to(edit_dataset_path(dataset))
  end

  it "blocks non-owner depositors from contributor management" do
    sign_in_as(email: "other@example.edu", name: "Other User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_contributors_path(dataset), params: {
      contributor: {
        name: "Blocked Contributor",
        role: "Data Curator"
      }
    }

    expect(response).to redirect_to(root_path)
    expect(dataset.contributors.count).to eq(0)
  end
end
