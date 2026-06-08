require "rails_helper"

RSpec.describe "Featured researchers", type: :request do
  before do
    FeaturedResearcher.delete_all
    ActiveRecord::Base.connection.reset_pk_sequence!(FeaturedResearcher.table_name)
  end

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

  def valid_params(name: "Researcher One", is_active: true)
    {
      featured_researcher: {
        name: name,
        question: "What inspired this work?",
        testimonial: "This was helpful.",
        bio: "Researcher biography.",
        photo_url: "https://example.org/headshot.jpg",
        dataset_url: "https://example.org/dataset",
        article_url: "https://example.org/article",
        is_active: is_active
      }
    }
  end

  it "shows only active spotlights to guests" do
    active = FeaturedResearcher.create!(
      name: "Active Spotlight",
      is_active: true,
      dataset_url: "https://example.org/dataset/active",
      created_at: Time.current,
      updated_at: Time.current
    )
    FeaturedResearcher.create!(
      name: "Inactive Spotlight",
      is_active: false,
      dataset_url: "https://example.org/dataset/inactive",
      created_at: Time.current,
      updated_at: Time.current
    )

    get researcher_spotlights_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(active.name)
    expect(response.body).not_to include("Inactive Spotlight")
    expect(response.body).not_to include("New Researcher Spotlight")
  end

  it "shows all spotlights and management actions to admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    FeaturedResearcher.create!(
      name: "Inactive Spotlight",
      is_active: false,
      dataset_url: "https://example.org/dataset/inactive",
      created_at: Time.current,
      updated_at: Time.current
    )

    get featured_researchers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Inactive Spotlight")
    expect(response.body).to include("New Researcher Spotlight")
    expect(response.body).to include("Status:")
  end

  it "allows admins to create a spotlight and redirects to preview" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    post featured_researchers_path, params: valid_params(name: "Created Spotlight")

    created = FeaturedResearcher.order(:created_at).last
    expect(response).to redirect_to(preview_featured_researcher_path(created))
    expect(created.name).to eq("Created Spotlight")
  end

  it "renders unprocessable content for invalid create" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    post featured_researchers_path, params: valid_params(name: "")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("prevented this researcher spotlight from being saved")
  end

  it "allows admins to update and delete a spotlight" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    spotlight = FeaturedResearcher.create!(
      name: "Editable Spotlight",
      is_active: false,
      dataset_url: "https://example.org/dataset/editable",
      created_at: Time.current,
      updated_at: Time.current
    )

    patch featured_researcher_path(spotlight), params: valid_params(name: "Updated Spotlight", is_active: true)

    expect(response).to redirect_to(preview_featured_researcher_path(spotlight))
    expect(spotlight.reload.name).to eq("Updated Spotlight")
    expect(spotlight.is_active).to be(true)

    expect {
      delete featured_researcher_path(spotlight)
    }.to change(FeaturedResearcher, :count).by(-1)

    expect(response).to redirect_to(featured_researchers_path)
  end

  it "blocks non-admin users from management actions" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor User", role: "depositor")

    spotlight = FeaturedResearcher.create!(
      name: "Locked Spotlight",
      is_active: true,
      dataset_url: "https://example.org/dataset/locked",
      created_at: Time.current,
      updated_at: Time.current
    )

    get new_featured_researcher_path
    expect(response).to redirect_to(root_path)

    get preview_featured_researcher_path(spotlight)
    expect(response).to redirect_to(root_path)

    patch featured_researcher_path(spotlight), params: valid_params(name: "Should Not Update")
    expect(response).to redirect_to(root_path)
    expect(spotlight.reload.name).to eq("Locked Spotlight")
  end
end
