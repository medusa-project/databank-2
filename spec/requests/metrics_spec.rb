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

  it "serves the public metrics dashboard without authentication" do
    get metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Illinois Data Bank Metrics")
  end

  it "blocks admin metrics for non-admin users" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor", role: "depositor")

    get admin_metrics_path

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "serves admin metrics for admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    get admin_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Metrics Exports")
    expect(response.body).to include("Datasets TSV")
    expect(response.body).to include("Download Metrics Details")
  end

  it "blocks dedicated download metrics page for non-curator users" do
    sign_in_as(email: "depositor-metrics-detail@example.edu", name: "Depositor Detail", role: "depositor")

    get download_metrics_path

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "serves dedicated download metrics page for curators" do
    sign_in_as(email: "curator-metrics-detail@example.edu", name: "Curator Detail", role: "curator")

    get download_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Download Metrics")
    expect(response.body).to include("Dataset Downloads")
    expect(response.body).to include("Datafile Downloads")
    expect(response.body).not_to include("Download breakdown JSON")
  end

  it "ensures download metrics are generated before rendering download metrics page" do
    sign_in_as(email: "admin-metrics-generate@example.edu", name: "Admin Generate", role: "admin")
    allow(Metric).to receive(:ensure_download_metrics)

    get download_metrics_path

    expect(response).to have_http_status(:ok)
    expect(Metric).to have_received(:ensure_download_metrics)
  end

  it "still renders download metrics page when ensure step fails" do
    sign_in_as(email: "admin-metrics-error@example.edu", name: "Admin Metrics Error", role: "admin")
    allow(Metric).to receive(:ensure_download_metrics).and_raise(StandardError, "storage unavailable")

    get download_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Download Metrics")
    expect(flash[:alert]).to eq("Some download metrics files are temporarily unavailable.")
  end

  it "lists only years with available metric files" do
    sign_in_as(email: "curator-availability@example.edu", name: "Curator Availability", role: "curator")

    allow(Metric).to receive(:ensure_download_metrics)
    allow(Metric).to receive(:current_calendar_year).and_return(2026)
    allow(Metric).to receive(:current_fiscal_year).and_return(26)

    allow(Metric).to receive(:year_metric_available?) do |metric_type:, year:, slice_type:|
      [
        [metric_type, year, slice_type],
        [metric_type, year.to_i, slice_type]
      ].any? do |triple|
        [
          [:dataset_downloads, 2026, :calendar],
          [:dataset_downloads, 2024, :calendar],
          [:dataset_downloads, 25, :fiscal],
          [:datafile_downloads, 26, :fiscal],
          [:datafile_downloads, 2023, :calendar]
        ].include?(triple)
      end
    end

    get download_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dataset Downloads 2026 (Calendar Year)")
    expect(response.body).to include("Dataset Downloads 2024 (Calendar Year)")
    expect(response.body).to include("Dataset Downloads FY25 (Fiscal Year)")
    expect(response.body).not_to include("Dataset Downloads 2025 (Calendar Year)")
    expect(response.body).not_to include("Dataset Downloads FY24 (Fiscal Year)")
    expect(response.body).to include("Datafile Downloads 2023 (Calendar Year)")
    expect(response.body).to include("Datafile Downloads FY26 (Fiscal Year)")
    expect(response.body).not_to include("Datafile Downloads 2026 (Calendar Year)")
  end

  it "serves archived content csv publicly" do
    get archived_content_csv_metrics_path(format: :csv)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    expect(response.body.lines.first).to include("doi")
  end

  it "serves config-backed datafiles, funders, and related materials csv files publicly" do
    get datafiles_csv_metrics_path(format: :csv)
    expect(response).to have_http_status(:ok)

    get funders_csv_metrics_path(format: :csv)
    expect(response).to have_http_status(:ok)

    get related_materials_csv_metrics_path(format: :csv)
    expect(response).to have_http_status(:ok)
  end

  it "returns filtered archived download metric CSV for authorized users" do
    sign_in_as(email: "curator-archive@example.edu", name: "Curator Archive", role: "curator")
    allow(Metric).to receive(:retrieve_archived_metric_from_storage)
      .with(:dataset_downloads, 2024, :calendar)
      .and_return("dataset_key,doi,download_date,tally\nIDB-123,10.1/abc,2024-01-01,2\n")

    get archived_download_metric_path(metric_type: :dataset_downloads, year: 2024, slice_type: :calendar)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    expect(response.body).to include("dataset_key,doi,download_date,tally")
  end

  it "returns bad request for invalid archived download metric parameters" do
    sign_in_as(email: "curator-archive-invalid@example.edu", name: "Curator Archive Invalid", role: "curator")

    get archived_download_metric_path(metric_type: :bogus, year: "xyz", slice_type: :monthly)

    expect(response).to have_http_status(:bad_request)
  end

  it "returns bad request for invalid zip group" do
    sign_in_as(email: "curator-zip-invalid@example.edu", name: "Curator Zip Invalid", role: "curator")

    get metrics_download_zip_path(group: :unknown)

    expect(response).to have_http_status(:bad_request)
  end

  it "returns download zip for valid zip group" do
    sign_in_as(email: "curator-zip@example.edu", name: "Curator Zip", role: "curator")
    allow(Metric).to receive(:build_zip_for_group).with(:dataset_calendar).and_return("ZIPDATA")

    get metrics_download_zip_path(group: :dataset_calendar)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("application/zip")
  end

  it "blocks refresh actions for non-admin users" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor", role: "depositor")

    post refresh_datasets_tsv_metrics_path

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "enqueues refresh actions for admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect do
      post refresh_datasets_tsv_metrics_path
    end.to have_enqueued_job(MetricRefreshJob).with(:datasets_tsv)

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
