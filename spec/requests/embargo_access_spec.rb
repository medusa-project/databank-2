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
    dataset = create(:dataset, :published,
      title: "Metadata Embargo Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 30
    )

    get datasets_path, params: { q: "Metadata Embargo Dataset" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(dataset_path(dataset))
  end

  it "shows file-embargoed datasets in public search before release" do
    dataset = create(:dataset, :published,
      title: "File Embargo Dataset",
      embargo: Dataset::EMBARGO_FILE,
      release_date: Date.current + 30
    )

    get datasets_path, params: { q: "File Embargo Dataset" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))
  end

  it "blocks guest download for file embargo but allows owner access" do
    dataset = create(:dataset, :published,
      title: "Embargoed Download Dataset",
      depositor_email: "owner-download@example.edu",
      embargo: Dataset::EMBARGO_FILE,
      release_date: Date.current + 30
    )

    datafile = create(:datafile, dataset: dataset)

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:forbidden)

    sign_in_as(email: "owner-download@example.edu", name: "Owner Download", role: "depositor")

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
  end

  it "blocks guest download for metadata embargo before release" do
    dataset = create(:dataset, :published,
      title: "Metadata Embargo Download Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 30
    )

    datafile = create(:datafile, dataset: dataset)

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(root_path)
  end

  it "allows guest access once a metadata embargo is released" do
    dataset = create(:dataset, :published,
      title: "Released Metadata Embargo Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current - 1
    )

    datafile = create(:datafile, dataset: dataset)

    get datasets_path, params: { q: "Released Metadata Embargo Dataset" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
  end

  it "allows guest access on the exact metadata embargo release date" do
    dataset = create(:dataset, :published,
      title: "Exact Date Metadata Release Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current
    )

    datafile = create(:datafile, dataset: dataset)

    get datasets_path, params: { q: "Exact Date Metadata Release Dataset" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))

    get dataset_path(dataset)
    expect(response).to have_http_status(:ok)

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
  end

  it "allows guest file download on the exact file embargo release date" do
    dataset = create(:dataset, :published,
      title: "Exact Date File Release Dataset",
      embargo: Dataset::EMBARGO_FILE,
      release_date: Date.current
    )

    datafile = create(:datafile, dataset: dataset)

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
  end

  it "requires login for guest access to metadata-embargoed dataset show before release" do
    dataset = create(:dataset, :published,
      title: "Private Metadata Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 15
    )

    get dataset_path(dataset)

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(login_path)
  end

  it "allows owner depositor to view their metadata-embargoed dataset before release" do
    dataset = create(:dataset, :published,
      title: "Owner Metadata Dataset",
      depositor_email: "owner-visible@example.edu",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 15
    )

    sign_in_as(email: "owner-visible@example.edu", name: "Owner Visible", role: "depositor")

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Owner Metadata Dataset")
  end

  it "blocks non-owner depositor from metadata-embargoed dataset before release" do
    dataset = create(:dataset, :published,
      title: "Other User Metadata Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 15
    )

    sign_in_as(email: "different-depositor@example.edu", name: "Different Depositor", role: "depositor")

    get dataset_path(dataset)

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(root_path)
  end

  it "shows embargoed owned datasets in depositor search with depositor facets hidden" do
    create(:dataset, :published,
      title: "Owner Embargo Search Dataset",
      depositor_email: "search-owner@example.edu",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 15
    )

    sign_in_as(email: "search-owner@example.edu", name: "Search Owner", role: "depositor")

    get datasets_path, params: { q: "Owner Embargo Search Dataset" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Owner Embargo Search Dataset")
    expect(response.body).to include("Publication State")
    expect(response.body).not_to include("Depositor")
  end

  it "shows metadata-embargoed datasets to admins and keeps admin depositor facet" do
    dataset = create(:dataset, :published,
      title: "Admin Embargo Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 15
    )

    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    get datasets_path, params: { q: "Admin Embargo Dataset" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))
    expect(response.body).to include("Depositor")
  end

  it "shows metadata-embargoed datasets to curators before release" do
    dataset = create(:dataset, :published,
      title: "Curator Embargo Dataset",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 15
    )

    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    get dataset_path(dataset)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Curator Embargo Dataset")

    get datasets_path, params: { q: "Curator Embargo Dataset" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset_path(dataset))
    expect(response.body).to include("Depositor")
  end
end
