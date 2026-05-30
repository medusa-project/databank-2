require "rails_helper"

RSpec.describe "Embargo access", type: :request do
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

  it "hides metadata-embargoed datasets from guests before release" do
    dataset = Dataset.create!(
      title: "Metadata Embargo Dataset",
      description: "Should not be publicly listed yet",
      keywords: "embargo",
      subject: "Data Curation",
      owner_uid: "owner-meta",
      depositor_name: "Owner Meta",
      depositor_email: "owner-meta@example.edu",
      publication_state: :published,
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 30
    )

    get datasets_path, params: { q: "Metadata Embargo Dataset" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(dataset_path(dataset))
  end

  it "shows file-embargoed datasets in public search before release" do
    dataset = Dataset.create!(
      title: "File Embargo Dataset",
      description: "Metadata should remain visible",
      keywords: "embargo",
      subject: "Data Curation",
      owner_uid: "owner-file",
      depositor_name: "Owner File",
      depositor_email: "owner-file@example.edu",
      publication_state: :published,
      embargo: Dataset::EMBARGO_FILE,
      release_date: Date.current + 30
    )

    get datasets_path, params: { q: "File Embargo Dataset" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))
  end

  it "blocks guest download for file embargo but allows owner access" do
    dataset = Dataset.create!(
      title: "Embargoed Download Dataset",
      description: "Download should be blocked for guests",
      keywords: "embargo",
      subject: "Data Curation",
      owner_uid: "owner-download",
      depositor_name: "Owner Download",
      depositor_email: "owner-download@example.edu",
      publication_state: :published,
      embargo: Dataset::EMBARGO_FILE,
      release_date: Date.current + 30
    )

    upload = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/analysis.csv"),
      "text/csv"
    )

    datafile = dataset.datafiles.create!(
      binary: upload,
      description: "Embargoed file"
    )

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:forbidden)

    sign_in_as(email: "owner-download@example.edu", name: "Owner Download", role: "depositor")

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
  end

  it "blocks guest download for metadata embargo before release" do
    dataset = Dataset.create!(
      title: "Metadata Embargo Download Dataset",
      description: "Download should be blocked for guests",
      keywords: "embargo",
      subject: "Data Curation",
      owner_uid: "owner-meta-download",
      depositor_name: "Owner Meta Download",
      depositor_email: "owner-meta-download@example.edu",
      publication_state: :published,
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 30
    )

    upload = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/analysis.csv"),
      "text/csv"
    )

    datafile = dataset.datafiles.create!(
      binary: upload,
      description: "Metadata embargoed file"
    )

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(root_path)
  end

  it "allows guest access once a metadata embargo is released" do
    dataset = Dataset.create!(
      title: "Released Metadata Embargo Dataset",
      description: "Should be public after release",
      keywords: "embargo",
      subject: "Data Curation",
      owner_uid: "owner-meta-released",
      depositor_name: "Owner Meta Released",
      depositor_email: "owner-meta-released@example.edu",
      publication_state: :published,
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current - 1
    )

    upload = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/analysis.csv"),
      "text/csv"
    )

    datafile = dataset.datafiles.create!(
      binary: upload,
      description: "Released metadata embargo file"
    )

    get datasets_path, params: { q: "Released Metadata Embargo Dataset" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
  end
end
