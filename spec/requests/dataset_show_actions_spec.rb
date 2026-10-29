require "rails_helper"

RSpec.describe "Dataset show actions", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "offers pre-publication review to a dataset owner when a draft is complete" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create(:dataset, :with_required_metadata, depositor_email: "owner@example.edu")

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pre-Publication Review")
    expect(response.body).not_to include("Curator Publish")
    expect(response.body).to include(request_review_dataset_path(dataset))
  end

  it "offers pre-publication review to an editor who is not the depositor" do
    sign_in_as(email: "editor@example.edu", name: "Editor User", role: "depositor")
    dataset = create(:dataset, :with_required_metadata, depositor_email: "owner@example.edu")
    DatasetAccessGrant.create!(dataset: dataset, email: "editor@example.edu", access_level: :editor)

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pre-Publication Review")
    expect(response.body).to include(request_review_dataset_path(dataset))
    expect(response.body).not_to include("Curator Publish")
  end

  [ "curator", "admin" ].each do |role|
    it "offers curator publish to a #{role} when a draft is complete" do
      sign_in_as(email: "#{role}@example.edu", name: "#{role.titleize} User", role: role)
      dataset = create(:dataset, :with_required_metadata)

      get dataset_path(dataset)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Curator Publish")
      expect(response.body).to include(publish_dataset_path(dataset))
      expect(response.body).not_to include("Pre-Publication Review")
      controls = Nokogiri::HTML(response.body).at_css(".idb-curator-control-links")
      expect(controls.css("a").map { |link| [ link.text, link["href"] ] }).to eq([
        [ "Suppression Controls", suppression_controls_dataset_path(dataset) ],
        [ "Version Controls", version_controls_dataset_path(dataset) ],
        [ "Curator Notes", dataset_notes_path(dataset) ]
      ])
    end
  end

  it "does not offer publication actions when a draft is incomplete" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create(:dataset, depositor_email: "owner@example.edu")

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    status_text = document.css(".dataset-show-status").text.squish
    expect(status_text).to include("Required elements for a complete dataset missing:")
    dataset.missing_publish_fields.each do |field|
      expect(status_text).to include(field)
    end
    expect(response.body).not_to include("Pre-Publication Review")
    expect(response.body).not_to include("Curator Publish")
    expect(document.css("form[action='#{request_review_dataset_path(dataset)}']")).to be_empty
    expect(document.css("form[action='#{publish_dataset_path(dataset)}']")).to be_empty
  end

  it "shows review guidance when an unmodified review request already exists" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create(:dataset, :with_required_metadata, depositor_email: "owner@example.edu")
    dataset.review_requests.create!(
      requester_name: "Owner User",
      requester_email: "owner@example.edu",
      requested_at: Time.current
    )

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Find out more about Pre-Publication review")
    expect(response.body).not_to include("Pre-Publication Review")
  end

  it "offers a new review request after a prior review request is modified" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")
    dataset = create(:dataset, :with_required_metadata, depositor_email: "owner@example.edu")
    review_request = dataset.review_requests.create!(
      requester_name: "Owner User",
      requester_email: "owner@example.edu",
      requested_at: Time.current
    )
    dataset.update!(description: "Updated after review.")

    expect(review_request.reload).to be_modified

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pre-Publication Review")
    expect(response.body).not_to include("Find out more about Pre-Publication review")
  end

  it "offers review rather than curator publish for a version draft" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")
    dataset = create(:dataset, :with_required_metadata, :hold_temp_version)

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pre-Publication Review")
    expect(response.body).not_to include("Curator Publish")
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name,
        role: role
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
