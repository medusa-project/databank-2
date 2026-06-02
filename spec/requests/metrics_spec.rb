require "rails_helper"

RSpec.describe "Metrics", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  before do
    clear_enqueued_jobs
    Metric::LOCK_KEYS.each { |key| Metric.clear_in_progress(key) }
  end

  it "serves the metrics index without authentication" do
    get metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Metrics")
  end

  it "blocks refresh actions for non-admin users" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor", role: "depositor")

    get refresh_dataset_downloads_metrics_path

    expect(response).to redirect_to(metrics_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized")
  end

  it "enqueues refresh actions for admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect do
      get refresh_dataset_downloads_metrics_path
    end.to have_enqueued_job(MetricRefreshJob).with(:dataset_downloads_json)

    expect(response).to redirect_to(metrics_path)
  end

  it "returns the public datafiles simple list" do
    dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_NONE)
    datafile = create(:datafile, dataset: dataset)

    get datafiles_simple_list_metrics_path(format: :json)

    expect(response).to have_http_status(:ok)
    parsed = JSON.parse(response.body)
    expect(parsed).to be_an(Array)
    expect(parsed).to include(a_hash_including(
      "filename" => datafile.binary_name,
      "web_id" => datafile.web_id,
      "dataset_key" => dataset.key
    ))
  end

  it "records tallies when a public datafile is downloaded" do
    dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_NONE, identifier: "10.5555/TEST-METRICS")
    datafile = create(:datafile, dataset: dataset)

    get download_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(DayFileDownload.count).to eq(1)
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)&.tally).to eq(1)
    expect(DatasetDownloadTally.find_by(dataset_key: dataset.key)&.tally).to eq(1)
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name,
        nickname: email.split("@").first,
        role: role
      }
    )

    get "/auth/developer/callback"
  end
end
