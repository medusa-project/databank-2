require "rails_helper"

RSpec.describe "Guides page", type: :request do
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

  it "renders a nested TOC and content from public guide records" do
    section = Guide::Section.create!(anchor: "submission", label: "Submission", ordinal: 1, public: true, heading: "Submission")
    section.body = "<p>Section body text</p>"
    section.save!

    item = Guide::Item.create!(section_id: section.id, anchor: "login", label: "Log In", ordinal: 1, public: true, heading: "Log in")
    item.body = "<p>Item body text</p>"
    item.save!

    subitem = Guide::Subitem.create!(item_id: item.id, anchor: "upload_tools", label: "Upload Tools", ordinal: 1, public: true, heading: "Upload")
    subitem.body = "<p>Subitem body text</p>"
    subitem.save!

    get guides_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("href=\"#submission\"")
    expect(response.body).to include("href=\"#login\"")
    expect(response.body).to include("href=\"#upload_tools\"")
    expect(response.body).to include("Section body text")
    expect(response.body).to include("Item body text")
    expect(response.body).to include("Subitem body text")
  end

  it "shows only public guides content in TOC and body" do
    public_section = Guide::Section.create!(anchor: "public-section", label: "Public Section", ordinal: 1, public: true, heading: "Public")
    private_section = Guide::Section.create!(anchor: "private-section", label: "Private Section", ordinal: 2, public: false, heading: "Private")

    Guide::Item.create!(section_id: public_section.id, anchor: "public-item", label: "Public Item", ordinal: 1, public: true, heading: "Public Item")
    Guide::Item.create!(section_id: public_section.id, anchor: "private-item", label: "Private Item", ordinal: 2, public: false, heading: "Private Item")
    Guide::Item.create!(section_id: private_section.id, anchor: "private-section-item", label: "Private Section Item", ordinal: 1, public: true, heading: "Private Section Item")

    get guides_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Public Section")
    expect(response.body).to include("Public Item")
    expect(response.body).not_to include("Private Section")
    expect(response.body).not_to include("Private Item")
    expect(response.body).not_to include("Private Section Item")
  end
end
