require "rails_helper"

RSpec.describe "Guide items and subitems", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  let!(:section) { Guide::Section.create!(label: "Depositing", anchor: "depositing", ordinal: 1, public: true) }
  let!(:other_section) { Guide::Section.create!(label: "Sharing", anchor: "sharing", ordinal: 2, public: true) }
  let!(:item) { Guide::Item.create!(section_id: section.id, label: "Prepare files", anchor: "prepare-files", ordinal: 1, public: true) }
  let!(:other_item) { Guide::Item.create!(section_id: other_section.id, label: "Publish dataset", anchor: "publish-dataset", ordinal: 1, public: true) }
  let!(:subitem) { Guide::Subitem.create!(item_id: item.id, label: "Zip content", anchor: "zip-content", ordinal: 1, public: true) }
  let!(:other_subitem) { Guide::Subitem.create!(item_id: other_item.id, label: "Mint DOI", anchor: "mint-doi", ordinal: 1, public: true) }

  before do
    sign_in_as(email: "admin-guides@example.edu", name: "Guide Admin", role: "admin")
  end

  it "shows only items for the selected section" do
    get guide_items_path(section_id: section.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Manage items for section: Depositing")
    expect(response.body).to include("Prepare files")
    expect(response.body).not_to include("Publish dataset")
  end

  it "shows section picker when items index has no section context" do
    get guide_items_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Select a section to manage its items.")
    expect(response.body).to include("Depositing")
    expect(response.body).to include("Sharing")
  end

  it "renders the new item form with section context" do
    get new_guide_item_path(section_id: section.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Save Item")
    expect(response.body).to include("Depositing")
    expect(response.body).to include(CGI.escapeHTML(guide_items_path(section_id: section.id)))
  end

  it "creates an item and redirects back to the section item list" do
    post guide_items_path, params: {
      guide_item: {
        section_id: section.id,
        label: "Review metadata",
        anchor: "review-metadata",
        ordinal: 3,
        heading: "Review metadata",
        public: true,
        body: "<div>Check title and description</div>"
      }
    }

    expect(response).to redirect_to(guide_items_path(section_id: section.id))
    created = Guide::Item.find_by!(anchor: "review-metadata")
    expect(created.label).to eq("Review metadata")
    expect(created.section_id).to eq(section.id)
  end

  it "re-renders the new item form when create fails" do
    allow_any_instance_of(Guide::Item).to receive(:save).and_return(false)

    post guide_items_path, params: {
      guide_item: {
        section_id: section.id,
        label: "Broken item",
        anchor: "broken-item"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Save Item")
    expect(response.body).to include("Depositing")
  end

  it "updates an item and redirects back to its section" do
    patch guide_item_path(item), params: {
      guide_item: {
        label: "Prepare archive",
        heading: "Prepare archive files"
      }
    }

    expect(response).to redirect_to(guide_items_path(section_id: section.id))
    expect(item.reload.label).to eq("Prepare archive")
    expect(item.heading).to eq("Prepare archive files")
  end

  it "re-renders the edit item form when update fails" do
    allow_any_instance_of(Guide::Item).to receive(:update).and_return(false)

    patch guide_item_path(item), params: {
      guide_item: {
        label: "Still prepare files"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Save Item")
    expect(response.body).to include("Prepare files")
  end

  it "destroys an item and redirects back to its section" do
    delete guide_item_path(item)

    expect(response).to redirect_to(guide_items_path(section_id: section.id))
    expect(Guide::Item.exists?(item.id)).to be(false)
  end

  it "shows only subitems for the selected item" do
    get guide_subitems_path(item_id: item.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Manage subitems for item: Prepare files")
    expect(response.body).to include("Zip content")
    expect(response.body).not_to include("Mint DOI")
  end

  it "shows item picker when subitems index has no item context" do
    get guide_subitems_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Select an item to manage its subitems.")
    expect(response.body).to include("Prepare files")
    expect(response.body).to include("Publish dataset")
  end

  it "renders the new subitem form with item context" do
    get new_guide_subitem_path(item_id: item.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Save Subitem")
    expect(response.body).to include("Prepare files")
    expect(response.body).to include(CGI.escapeHTML(guide_subitems_path(item_id: item.id)))
  end

  it "creates a subitem and redirects back to the item subitem list" do
    post guide_subitems_path, params: {
      guide_subitem: {
        item_id: item.id,
        label: "Name files clearly",
        anchor: "name-files-clearly",
        ordinal: 2,
        heading: "Name files clearly",
        public: true,
        body: "<div>Use descriptive names</div>"
      }
    }

    expect(response).to redirect_to(guide_subitems_path(item_id: item.id))
    created = Guide::Subitem.find_by!(anchor: "name-files-clearly")
    expect(created.label).to eq("Name files clearly")
    expect(created.item_id).to eq(item.id)
  end

  it "re-renders the new subitem form when create fails" do
    allow_any_instance_of(Guide::Subitem).to receive(:save).and_return(false)

    post guide_subitems_path, params: {
      guide_subitem: {
        item_id: item.id,
        label: "Broken subitem",
        anchor: "broken-subitem"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Save Subitem")
    expect(response.body).to include("Prepare files")
  end

  it "updates a subitem and redirects back to its item" do
    patch guide_subitem_path(subitem), params: {
      guide_subitem: {
        label: "Compress content",
        heading: "Compress content before upload"
      }
    }

    expect(response).to redirect_to(guide_subitems_path(item_id: item.id))
    expect(subitem.reload.label).to eq("Compress content")
    expect(subitem.heading).to eq("Compress content before upload")
  end

  it "re-renders the edit subitem form when update fails" do
    allow_any_instance_of(Guide::Subitem).to receive(:update).and_return(false)

    patch guide_subitem_path(subitem), params: {
      guide_subitem: {
        label: "Still zip content"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Save Subitem")
    expect(response.body).to include("Zip content")
  end

  it "destroys a subitem and redirects back to its item" do
    delete guide_subitem_path(subitem)

    expect(response).to redirect_to(guide_subitems_path(item_id: item.id))
    expect(Guide::Subitem.exists?(subitem.id)).to be(false)
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
