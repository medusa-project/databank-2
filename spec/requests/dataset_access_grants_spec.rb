require "rails_helper"

RSpec.describe "Dataset access grants", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "allows a dataset owner to create and remove grants from the edit page" do
    dataset = create(:dataset, depositor_email: "owner@example.edu")

    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    expect {
      post dataset_dataset_access_grants_path(dataset), params: {
        dataset_access_grant: {
          email: "viewer@example.edu",
          access_level: "viewer"
        }
      }
    }.to change(DatasetAccessGrant, :count).by(1)

    grant = DatasetAccessGrant.find_by!(dataset: dataset, email: "viewer@example.edu")

    expect {
      delete dataset_dataset_access_grant_path(dataset, grant)
    }.to change(DatasetAccessGrant, :count).by(-1)
  end

  it "allows a viewer grant recipient to see a metadata-embargoed dataset in search and show" do
    dataset = create(:dataset, :published,
      title: "Granted Metadata Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 10
    )
    DatasetAccessGrant.create!(dataset: dataset, email: "viewer@example.edu", access_level: :viewer)

    sign_in_as(email: "viewer@example.edu", name: "Viewer User", role: "depositor")

    get datasets_path, params: { q: "Granted Metadata Dataset" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))

    get dataset_path(dataset)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Granted Metadata Dataset")
  end

  it "allows a viewer grant recipient to download files for a file-embargoed dataset" do
    dataset = create(:dataset, :published,
      embargo: Dataset::EMBARGO_FILE,
      release_date: Date.current + 10
    )
    datafile = create(:datafile, dataset: dataset)
    DatasetAccessGrant.create!(dataset: dataset, email: "viewer@example.edu", access_level: :viewer)

    sign_in_as(email: "viewer@example.edu", name: "Viewer User", role: "depositor")

    get download_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
  end

  it "allows an editor grant recipient to update dataset metadata" do
    dataset = create(:dataset, title: "Editable Dataset", depositor_email: "owner@example.edu")
    DatasetAccessGrant.create!(dataset: dataset, email: "editor@example.edu", access_level: :editor)

    sign_in_as(email: "editor@example.edu", name: "Editor User", role: "depositor")

    patch dataset_path(dataset), params: {
      dataset: {
        title: "Edited By Grant",
        description: dataset.description,
        keywords: dataset.keywords,
        subject: dataset.subject,
        license: dataset.license,
        publisher: dataset.publisher
      }
    }

    expect(response).to redirect_to(dataset_path(dataset))
    expect(dataset.reload.title).to eq("Edited By Grant")
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
