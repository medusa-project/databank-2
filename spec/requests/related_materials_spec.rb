require "rails_helper"

RSpec.describe "Related materials", type: :request do
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
      title: "Related Material Test Dataset",
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

  it "creates a related material for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_related_materials_path(dataset), params: {
      related_material: {
        title: "Project Article",
        uri: "https://example.org/article",
        relation_type: "IsSupplementTo",
        row_position: 1
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(dataset.related_materials.count).to eq(1)

    material = dataset.related_materials.first
    expect(material.title).to eq("Project Article")
    expect(material.relation_type).to eq("IsSupplementTo")
    expect(material.position).to eq(1)
  end

  it "rejects create when uri is provided without relation_type" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_related_materials_path(dataset), params: {
      related_material: {
        title: "Project Article",
        uri: "https://example.org/article",
        relation_type: ""
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:alert]).to include("Relation type can't be blank")
    expect(dataset.related_materials.count).to eq(0)
  end

  it "updates an existing related material for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    material = dataset.related_materials.create!(
      title: "Old Title",
      uri: "https://example.org/old",
      relation_type: "IsSupplementTo",
      row_position: 1
    )

    patch dataset_related_material_path(dataset, material), params: {
      related_material: {
        title: "Updated Title",
        uri: "https://example.org/new",
        relation_type: "IsSupplementedBy",
        datacite_list: "IsSupplementedBy",
        position: 2,
        row_position: 2
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))

    material.reload
    expect(material.title).to eq("Updated Title")
    expect(material.uri).to eq("https://example.org/new")
    expect(material.relation_type).to eq("IsSupplementedBy")
    expect(material.position).to eq(2)
    expect(material.row_position).to eq(2)
  end

  it "destroys an existing related material for an owned dataset" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create_owned_draft_dataset
    material = dataset.related_materials.create!(
      title: "Delete Me",
      uri: "https://example.org/delete",
      relation_type: "IsSupplementTo",
      row_position: 1
    )

    expect {
      delete dataset_related_material_path(dataset, material)
    }.to change(RelatedMaterial, :count).by(-1)

    expect(response).to redirect_to(edit_dataset_path(dataset))
  end

  it "blocks non-owner depositors from related material management" do
    sign_in_as(email: "other@example.edu", name: "Other User", role: "depositor")
    dataset = create_owned_draft_dataset

    post dataset_related_materials_path(dataset), params: {
      related_material: {
        title: "Blocked Material",
        uri: "https://example.org/blocked",
        relation_type: "IsSupplementTo"
      }
    }

    expect(response).to redirect_to(root_path)
    expect(dataset.related_materials.count).to eq(0)
  end
end
