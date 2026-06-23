require "rails_helper"

RSpec.describe "Guide CMS", type: :request do
  before do
    ActionText::RichText.where(record_type: [ "Guide::Section", "Guide::Item", "Guide::Subitem" ], name: "body").delete_all
    Guide::Subitem.delete_all
    Guide::Item.delete_all
    Guide::Section.delete_all

    connection = ActiveRecord::Base.connection
    connection.reset_pk_sequence!(Guide::Section.table_name)
    connection.reset_pk_sequence!(Guide::Item.table_name)
    connection.reset_pk_sequence!(Guide::Subitem.table_name)
  end

  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "allows admins to access guide cms indexes" do
    sign_in_as(email: "admin-guides@example.edu", name: "Guide Admin", role: "admin")

    get guide_sections_path
    expect(response).to have_http_status(:ok)

    get guide_items_path
    expect(response).to have_http_status(:ok)

    get guide_subitems_path
    expect(response).to have_http_status(:ok)
  end

  it "blocks non-admin users from guide cms" do
    sign_in_as(email: "depositor-guides@example.edu", name: "Guide Depositor", role: "depositor")

    get guide_sections_path
    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
  end

  it "creates and updates a section from cms" do
    sign_in_as(email: "admin-guides@example.edu", name: "Guide Admin", role: "admin")

    post guide_sections_path, params: {
      guide_section: {
        label: "Submission",
        anchor: "submission",
        ordinal: 1,
        heading: "Submission",
        public: true,
        body: "<p>Body text</p>"
      }
    }

    expect(response).to have_http_status(:redirect)
    section = Guide::Section.find_by!(anchor: "submission")
    expect(section.label).to eq("Submission")

    patch guide_section_path(section), params: {
      guide_section: {
        label: "Updated Submission",
        body: "<p>Updated body text</p>"
      }
    }

    expect(response).to have_http_status(:redirect)
    expect(section.reload.label).to eq("Updated Submission")
    expect(section.body.to_s).to include("Updated body text")
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
