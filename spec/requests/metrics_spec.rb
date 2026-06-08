require "rails_helper"

RSpec.describe "Metrics", type: :request do
  include ActiveJob::TestHelper

  def metric_config_for(tmpdir)
    {
      dataset_downloads_json: { relative_path: File.join(tmpdir, "dataset_downloads.json") },
      datafile_downloads_json: { relative_path: File.join(tmpdir, "datafile_downloads.json") },
      datasets_tsv: { relative_path: File.join(tmpdir, "datasets.tsv") },
      datafiles_csv: { relative_path: File.join(tmpdir, "datafiles.csv") },
      container_contents_csv: { relative_path: File.join(tmpdir, "container_contents.csv") },
      funders_csv: { relative_path: File.join(tmpdir, "funders.csv") },
      related_materials_csv: { relative_path: File.join(tmpdir, "related_materials.csv") },
      dataset_report_csv: { relative_path: File.join(tmpdir, "dataset_report.csv") },
      dataset_report_text: { relative_path: File.join(tmpdir, "dataset_report.txt") }
    }
  end

  def with_metric_config
    Dir.mktmpdir("metrics-controller-spec") do |tmpdir|
      stub_const("METRICS_CONFIG", metric_config_for(tmpdir))
      yield tmpdir
    end
  end

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
    expect(response.body).to include("Metrics exports")
  end

  it "serves admin metrics for curators" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    get admin_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Metrics exports")
  end

  it "blocks refresh actions for non-admin users" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor", role: "depositor")

    get refresh_dataset_downloads_metrics_path

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "enqueues refresh actions for admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect do
      get refresh_dataset_downloads_metrics_path
    end.to have_enqueued_job(MetricRefreshJob).with(:dataset_downloads_json)

    expect(response).to redirect_to(metrics_path)
  end

  it "enqueues refresh actions for curators" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

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

  it "serves public dataset download metrics json" do
    get dataset_downloads_metrics_path(format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("application/json")
    expect(JSON.parse(response.body)).to have_key("dataset_downloads")
  end

  it "serves public datafile download metrics json" do
    get file_downloads_metrics_path(format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("application/json")
    expect(JSON.parse(response.body)).to have_key("datafile_downloads")
  end

  it "serves archived content csv publicly" do
    get archived_content_csv_metrics_path(format: :csv)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    expect(response.body.lines.first).to include("doi")
  end

  it "serves config-backed datafiles, funders, and related materials csv files publicly" do
    with_metric_config do |tmpdir|
      File.write(File.join(tmpdir, "datafiles.csv"), "a,b\n1,2\n")
      File.write(File.join(tmpdir, "funders.csv"), "doi,funder,grant\n10.1,NSF,123\n")
      File.write(File.join(tmpdir, "related_materials.csv"), "doi,relation\n10.1,IsSupplementTo\n")

      get datafiles_csv_metrics_path(format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("a,b")

      get funders_csv_metrics_path(format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("doi,funder,grant")

      get related_materials_csv_metrics_path(format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("doi,relation")
    end
  end

  it "returns not found when a config-backed csv file is missing" do
    with_metric_config do
      get datafiles_csv_metrics_path(format: :csv)

      expect(response).to have_http_status(:not_found)
    end
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

  it "does not enqueue a refresh when the metric is already in progress" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")
    allow(Metric).to receive(:in_progress?).with(:dataset_downloads_json).and_return(true)

    expect do
      get refresh_dataset_downloads_metrics_path
    end.not_to have_enqueued_job(MetricRefreshJob)

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("already in progress")
  end

  it "clears the in-progress flag and shows an alert when refresh enqueue fails" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")
    allow(Metric).to receive(:in_progress?).with(:funders_csv).and_return(false)
    allow(Metric).to receive(:set_in_progress).with(:funders_csv)
    allow(Metric).to receive(:clear_in_progress).with(:funders_csv)
    allow(MetricRefreshJob).to receive(:perform_later).with(:funders_csv).and_raise(StandardError.new("queue unavailable"))
    allow(Rails.logger).to receive(:error)

    get refresh_funders_csv_metrics_path

    expect(Metric).to have_received(:clear_in_progress).with(:funders_csv)
    expect(Rails.logger).to have_received(:error).with(/Unable to enqueue metric refresh for funders_csv: queue unavailable/)
    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("Unable to start Funders CSV refresh right now")
  end

  it "enqueues the remaining refresh actions for admins" do
    sign_in_as(email: "admin2@example.edu", name: "Admin User Two", role: "admin")

    expect do
      get refresh_datafile_downloads_metrics_path
      get refresh_datasets_tsv_metrics_path
      get refresh_datafiles_csv_metrics_path
      get refresh_container_csv_metrics_path
      get refresh_related_materials_csv_metrics_path
      get refresh_container_contents_csv_metrics_path
    end.to have_enqueued_job(MetricRefreshJob).exactly(5).times

    enqueued_metric_keys = enqueued_jobs.map { |job| job[:args].first.fetch("value") }

    expect(enqueued_metric_keys).to include(
      "datafile_downloads_json",
      "datasets_tsv",
      "datafiles_csv",
      "container_contents_csv",
      "related_materials_csv"
    )
    expect(flash[:alert]).to include("already in progress")
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
