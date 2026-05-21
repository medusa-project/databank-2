require "test_helper"

class DatasetsWorkflowTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess::FixtureFile

  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  test "depositor can create edit and publish a dataset with contact creator" do
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

    assert_redirected_to dataset_path(dataset)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Draft Dataset"

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
    assert_redirected_to dataset_path(dataset)

    post dataset_creators_path(dataset), params: {
      creator: {
        name: "Researcher One",
        email: "researcher@example.edu",
        contact: true,
        position: 1
      }
    }
    assert_redirected_to edit_dataset_path(dataset)

    post dataset_datafiles_path(dataset), params: {
      datafile: {
        binary: fixture_file_upload("analysis.csv", "text/csv"),
        description: "Primary analysis file"
      }
    }
    assert_redirected_to edit_dataset_path(dataset)

    datafile = dataset.datafiles.order(:created_at).last
    assert datafile.binary.attached?
    assert_equal "analysis.csv", datafile.binary_name

    get download_dataset_datafile_path(dataset, datafile)
    assert_response :success
    assert_includes response.headers["Content-Disposition"], "attachment; filename=\"analysis.csv\""
    assert_includes response.body, "column_a,column_b"

    post publish_dataset_path(dataset)
    assert_redirected_to dataset_path(dataset)

    dataset.reload
    assert dataset.published?
    assert_equal "Updated Dataset", dataset.title
    assert_equal "climate,temperature,time-series", dataset.keywords
    assert_equal "Earth Systems", dataset.subject
    assert_equal "CC0", dataset.license
    assert_equal "University Library", dataset.publisher
    assert_equal "10.5555/#{dataset.key}", dataset.identifier
  end

  private

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
    assert_response :redirect
  end
end
