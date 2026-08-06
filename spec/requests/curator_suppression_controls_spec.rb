require "rails_helper"

RSpec.describe "Curator suppression controls", type: :request do
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

  it "allows curator to open suppression controls" do
    dataset = create(:dataset, :published, title: "Suppression Controls Dataset")
    sign_in_as(email: "curator-controls@example.edu", name: "Curator Controls", role: "curator")

    get suppression_controls_dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Suppression Control Buttons")
    expect(response.body).to include("Temporarily Suppress File(s) Only")
  end

  it "blocks non-curator from suppression controls" do
    dataset = create(:dataset, :published, title: "Suppression Forbidden Dataset")
    sign_in_as(email: "depositor-controls@example.edu", name: "Depositor Controls", role: "depositor")

    get suppression_controls_dataset_path(dataset)

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(root_path)
  end

  it "temporarily suppresses files through suppression action dispatcher" do
    dataset = create(:dataset, :published,
      title: "Suppress Files Dataset",
      hold_state: Dataset::HOLD_NONE
    )

    sign_in_as(email: "curator-files@example.edu", name: "Curator Files", role: "curator")

    post suppression_action_dataset_path(dataset), params: { suppression_action: "temporarily_suppress_files" }

    expect(response).to redirect_to(dataset_path(dataset))
    expect(dataset.reload.hold_state).to eq(Dataset::HOLD_TEMP_FILE)
  end

  it "unsuppresses through suppression action dispatcher" do
    dataset = create(:dataset, :published,
      title: "Unsuppress Dataset",
      hold_state: Dataset::HOLD_TEMP_METADATA
    )

    sign_in_as(email: "curator-unsuppress@example.edu", name: "Curator Unsuppress", role: "curator")

    post suppression_action_dataset_path(dataset), params: { suppression_action: "unsuppress" }

    expect(response).to redirect_to(dataset_path(dataset))
    expect(dataset.reload.hold_state).to eq(Dataset::HOLD_NONE)
  end

  it "permanently suppresses metadata and sets tombstone date" do
    dataset = create(:dataset, :published,
      title: "Perm Suppress Metadata Dataset",
      hold_state: Dataset::HOLD_NONE,
      embargo: Dataset::EMBARGO_FILE,
      release_date: Date.current + 5
    )

    sign_in_as(email: "curator-perm@example.edu", name: "Curator Permanent", role: "curator")

    post suppression_action_dataset_path(dataset), params: { suppression_action: "permanently_suppress_metadata" }

    expect(response).to redirect_to(dataset_path(dataset))
    dataset.reload
    expect(dataset.hold_state).to eq(Dataset::HOLD_PERM_METADATA)
    expect(dataset.embargo).to eq(Dataset::EMBARGO_NONE)
    expect(dataset.tombstone_date).to eq(Date.current)
  end

  it "shows legacy fallback notice when temporary metadata suppression cannot update DataCite" do
    dataset = create(:dataset, :published,
      title: "Suppression DataCite Fallback",
      hold_state: Dataset::HOLD_NONE,
      identifier: "10.5555/fallback-datacite"
    )

    sign_in_as(email: "curator-datacite-fallback@example.edu", name: "Curator DOI Fallback", role: "curator")

    suppression_service = instance_double(Doi::SuppressionService, suppress_metadata: false)
    allow(Doi::SuppressionService).to receive(:new).and_return(suppression_service)

    post suppression_action_dataset_path(dataset), params: { suppression_action: "temporarily_suppress_metadata" }

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Dataset metadata and files have been temporarily suppressed in IDB, but DataCite was not updated.")
  end

  it "shows legacy fallback notice when unsuppress cannot update DataCite" do
    dataset = create(:dataset, :published,
      title: "Unsuppress DataCite Fallback",
      hold_state: Dataset::HOLD_TEMP_METADATA,
      identifier: "10.5555/fallback-unsuppress"
    )

    sign_in_as(email: "curator-unsuppress-fallback@example.edu", name: "Curator Unsuppress Fallback", role: "curator")

    suppression_service = instance_double(Doi::SuppressionService, unsuppress_metadata: false)
    allow(Doi::SuppressionService).to receive(:new).and_return(suppression_service)

    post suppression_action_dataset_path(dataset), params: { suppression_action: "unsuppress" }

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Dataset has been unsuppressed in IDB, but DataCite was not updated.")
  end

  it "shows legacy fallback notice when permanent file suppression cannot remove Globus copy" do
    dataset = create(:dataset, :published,
      title: "Globus Removal Fallback",
      hold_state: Dataset::HOLD_NONE
    )

    sign_in_as(email: "curator-globus-fallback@example.edu", name: "Curator Globus Fallback", role: "curator")

    globus_service = instance_double(Globus::SuppressionService, remove_from_public_download: false)
    allow(Globus::SuppressionService).to receive(:new).and_return(globus_service)

    post suppression_action_dataset_path(dataset), params: { suppression_action: "permanently_suppress_files" }

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Failed to remove from Globus Download.")
  end

  it "shows combined fallback alert when permanent metadata suppression side effects fail" do
    dataset = create(:dataset, :published,
      title: "Combined Fallback",
      hold_state: Dataset::HOLD_NONE,
      identifier: "10.5555/fallback-combined"
    )

    sign_in_as(email: "curator-combined-fallback@example.edu", name: "Curator Combined Fallback", role: "curator")

    doi_service = instance_double(Doi::SuppressionService, suppress_metadata: false)
    globus_service = instance_double(Globus::SuppressionService, remove_from_public_download: false)
    allow(Doi::SuppressionService).to receive(:new).and_return(doi_service)
    allow(Globus::SuppressionService).to receive(:new).and_return(globus_service)

    post suppression_action_dataset_path(dataset), params: { suppression_action: "permanently_suppress_metadata" }

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Failed to remove from DataCite or Globus Download.")
  end

  it "allows curator to designate a draft dataset as version-type draft" do
    dataset = create(:dataset,
      title: "Draft To Version",
      publication_state: :draft,
      hold_state: Dataset::HOLD_NONE
    )

    sign_in_as(email: "curator-draft-to-version@example.edu", name: "Curator Draft To Version", role: "curator")

    get draft_to_version_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    expect(dataset.reload.hold_state).to eq(Dataset::HOLD_TEMP_VERSION)
  end

  it "allows curator to toggle version-type draft back to standard draft" do
    dataset = create(:dataset,
      title: "Version To Draft",
      publication_state: :draft,
      hold_state: Dataset::HOLD_TEMP_VERSION
    )

    sign_in_as(email: "curator-version-to-draft@example.edu", name: "Curator Version To Draft", role: "curator")

    get version_to_draft_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    expect(dataset.reload.hold_state).to eq(Dataset::HOLD_NONE)
  end

  it "blocks publish for version-type drafts until toggled back" do
    dataset = create(:dataset,
      title: "Publish Guard Version Draft",
      publication_state: :draft,
      hold_state: Dataset::HOLD_TEMP_VERSION
    )

    sign_in_as(email: dataset.depositor_email, name: "Depositor Publish Guard", role: "depositor")

    post publish_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("Version drafts require pre-publication review before publishing.")
    expect(dataset.reload.publication_state).to eq("draft")
  end
end
