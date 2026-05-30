require "rails_helper"

RSpec.describe "Funders", type: :request do
  def sign_in_as(email:, name:, role:)
    OmniAuth.config.test_mode = true
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
  ensure
    OmniAuth.config.mock_auth[:developer] = nil
  end

  def create_owned_draft_dataset
    Dataset.create!(
      title: "Funder Test Dataset",
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

  it "creates a funder for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_funders_path(dataset), params: {
      funder: {
        name: "U.S. Department of Energy (DOE)",
        identifier: "10.13039/100000015",
        award_number: "DE-12345",
        row_position: 1
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(dataset.funders.count).to eq(1)
    expect(dataset.funders.first.name).to eq("U.S. Department of Energy (DOE)")
    expect(dataset.funders.first.award_number).to eq("DE-12345")
  end

  it "rejects invalid funder create and returns an alert message" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_funders_path(dataset), params: {
      funder: {
        name: "",
        identifier: "10.13039/100000015"
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:alert]).to include("Name can't be blank")
    expect(dataset.funders.count).to eq(0)
  end

  it "updates an existing funder on an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    funder = dataset.funders.create!(name: "Old Name", identifier: "10.1234/old")

    patch dataset_funder_path(dataset, funder), params: {
      funder: {
        name: "New Name",
        award_number: "NEW-1"
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    funder.reload
    expect(funder.name).to eq("New Name")
    expect(funder.award_number).to eq("NEW-1")
  end

  it "destroys an existing funder on an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    funder = dataset.funders.create!(name: "Delete Me", identifier: "10.1234/delete")

    expect {
      delete dataset_funder_path(dataset, funder)
    }.to change(Funder, :count).by(-1)

    expect(response).to redirect_to(edit_dataset_path(dataset))
  end

  it "blocks non-owner depositor from managing funders" do
    sign_in_as(email: "other@example.edu", name: "Other User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_funders_path(dataset), params: {
      funder: {
        name: "Blocked Funder"
      }
    }

    expect(response).to redirect_to(root_path)
    expect(dataset.funders.count).to eq(0)
  end
end
