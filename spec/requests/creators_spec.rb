require "rails_helper"

RSpec.describe "Creators", type: :request do
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
      title: "Creator Test Dataset",
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

  it "creates a creator for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_creators_path(dataset), params: {
      creator: {
        given_name: "Taylor",
        family_name: "Researcher",
        identifier: "0000-0002-1825-0097",
        identifier_scheme: "ORCID",
        row_order: 1,
        row_position: 1
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(dataset.creators.count).to eq(1)

    creator = dataset.reload.creators.first
    expect(creator.name).to eq("Taylor Researcher")
    expect(creator.identifier).to eq("0000-0002-1825-0097")
    expect(creator.identifier_scheme).to eq("ORCID")
    expect(creator.row_order).to eq(1)
    expect(creator.position).to eq(1)
  end

  it "rejects invalid creator create and returns an alert" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_creators_path(dataset), params: {
      creator: {
        given_name: "",
        family_name: "",
        institution_name: "",
        name: ""
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:alert]).to include("Creator must have either an institution name")
    expect(dataset.creators.count).to eq(0)
  end

  it "updates an existing creator for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    creator = dataset.creators.create!(name: "Old Name", row_position: 1)

    patch dataset_creator_path(dataset, creator), params: {
      creator: {
        given_name: "New",
        family_name: "Name",
        row_order: 9,
        position: 2,
        row_position: 2
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))

    creator.reload
    expect(creator.name).to eq("Old Name")
    expect(creator.given_name).to eq("New")
    expect(creator.family_name).to eq("Name")
    expect(creator.row_order).to eq(9)
    expect(creator.position).to eq(2)
  end

  it "keeps only one contact creator when setting a new contact" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    first_creator = dataset.creators.create!(name: "First Contact", is_contact: true)

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Second Contact",
        is_contact: true
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))

    first_creator.reload
    second_creator = dataset.creators.find_by(name: "Second Contact")

    expect(second_creator).to be_present
    expect(second_creator.is_contact).to eq(true)
    expect(second_creator.contact).to eq(true)
    expect(first_creator.is_contact).to eq(false)
    expect(first_creator.contact).to eq(false)
  end

  it "destroys an existing creator for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    creator = dataset.creators.create!(name: "Delete Me", row_position: 1)

    expect {
      delete dataset_creator_path(dataset, creator)
    }.to change(Creator, :count).by(-1)

    expect(response).to redirect_to(edit_dataset_path(dataset))
  end

  it "blocks non-owner depositors from creator management" do
    sign_in_as(email: "other@example.edu", name: "Other User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Blocked Creator"
      }
    }

    expect(response).to redirect_to(root_path)
    expect(dataset.creators.count).to eq(0)
  end

  describe "GET /datasets/:dataset_id/creators/orcid_lookup" do
    it "blocks non-owner depositors from ORCID lookup" do
      sign_in_as(email: "other@example.edu", name: "Other User", role: "depositor")
      dataset = create_owned_draft_dataset

      get orcid_lookup_dataset_creators_path(dataset), params: { family_name: "Smith" }

      expect(response).to redirect_to(root_path)
    end

    it "returns 422 when family_name and given_name are blank" do
      sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
      dataset = create_owned_draft_dataset

      get orcid_lookup_dataset_creators_path(dataset), params: { family_name: "", given_name: "" }

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)).to eq("error" => "Provide family_name or given_name")
    end

    it "returns 502 when ORCID lookup fails" do
      sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
      dataset = create_owned_draft_dataset

      allow(Net::HTTP).to receive(:start).and_raise(StandardError.new("timeout"))

      get orcid_lookup_dataset_creators_path(dataset), params: { family_name: "Smith" }

      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)).to eq("error" => "ORCID lookup unavailable")
    end

    it "returns mapped ORCID results and limits to 10 entries" do
      sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
      dataset = create_owned_draft_dataset

      expanded = (1..11).map do |i|
        {
          "orcid-id" => "0000-0000-0000-#{format('%04d', i)}",
          "family-names" => "Family#{i}",
          "given-names" => "Given#{i}",
          "institution-name" => "Inst#{i}"
        }
      end

      response_body = { "expanded-result" => expanded }.to_json
      orcid_response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(orcid_response).to receive(:body).and_return(response_body)

      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(orcid_response)
      allow(Net::HTTP).to receive(:start).and_yield(http).and_return(orcid_response)

      get orcid_lookup_dataset_creators_path(dataset), params: { family_name: "Smith", given_name: "Taylor" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["results"].size).to eq(10)
      expect(body["results"].first).to eq(
        "orcid" => "0000-0000-0000-0001",
        "family_name" => "Family1",
        "given_name" => "Given1",
        "institution" => "Inst1"
      )
      expect(body["results"].last["orcid"]).to eq("0000-0000-0000-0010")
    end
  end
end
