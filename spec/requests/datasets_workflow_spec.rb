require "rails_helper"

RSpec.describe "Datasets workflow", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "allows a depositor to create edit and publish a dataset with contact creator" do
    sign_in_as(email: "owner@example.edu", name: "Owner User", role: "depositor")

    post datasets_path, params: {
      dataset: {
        title: "Draft Dataset",
        description: "Initial description",
        keywords: "climate,temperature",
        subject: "Environmental Science",
        license: "CC-BY-4.0",
        publisher: "Illinois Data Bank"
      }
    }
    dataset = Dataset.order(:created_at).last

    expect(response).to redirect_to(dataset_path(dataset))

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Draft Dataset")

    patch dataset_path(dataset), params: {
      dataset: {
        title: "Updated Dataset",
        description: "Updated description",
        keywords: "climate,temperature,time-series",
        subject: "Earth Systems",
        license: "CC0",
        publisher: "University Library"
      }
    }
    expect(response).to redirect_to(dataset_path(dataset))

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Researcher One",
        email: "researcher@example.edu",
        contact: true,
        position: 1
      }
    }
    expect(response).to redirect_to(edit_dataset_path(dataset))

    csv_fixture = Rails.root.join("test/fixtures/files/analysis.csv")
    uploaded_file = Rack::Test::UploadedFile.new(csv_fixture, "text/csv")

    post dataset_datafiles_path(dataset), params: {
      datafile: {
        binary: uploaded_file,
        description: "Primary analysis file"
      }
    }
    expect(response).to redirect_to(edit_dataset_path(dataset))

    datafile = dataset.datafiles.order(:created_at).last
    expect(datafile.binary).to be_attached
    expect(datafile.binary_name).to eq("analysis.csv")

    get download_dataset_datafile_path(dataset, datafile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include('attachment; filename="analysis.csv"')
    expect(response.body).to include("column_a,column_b")

    post publish_dataset_path(dataset)
    expect(response).to redirect_to(dataset_path(dataset))

    dataset.reload
    expect(dataset).to be_published
    expect(dataset.title).to eq("Updated Dataset")
    expect(dataset.keywords).to eq("climate,temperature,time-series")
    expect(dataset.subject).to eq("Earth Systems")
    expect(dataset.license).to eq("CC0")
    expect(dataset.publisher).to eq("University Library")
    expect(dataset.identifier).to eq("10.5555/#{dataset.key}")
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
