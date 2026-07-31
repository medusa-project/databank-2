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
    expect(response.body).to include("Datasets TSV")
    expect(response.body).to include("Dataset-level export with core descriptive and usage fields")
    expect(response.body).to include("Field definitions")
    expect(response.body).to include("Download Metrics Details")
  end

  it "blocks dedicated download metrics page for non-curator users" do
    sign_in_as(email: "depositor-metrics-detail@example.edu", name: "Depositor Detail", role: "depositor")

    get curator_download_metrics_path

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "serves dedicated download metrics page for curators" do
    sign_in_as(email: "curator-metrics-detail@example.edu", name: "Curator Detail", role: "curator")

    get curator_download_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Download Metrics")
    expect(response.body).to include("Calendar Year Totals")
    expect(response.body).to include("Fiscal Year Totals")
    expect(response.body).to include("Download breakdown JSON")
  end

  it "blocks download metrics breakdown JSON for non-curator users" do
    sign_in_as(email: "depositor-breakdown@example.edu", name: "Depositor Breakdown", role: "depositor")

    get download_metrics_breakdown_metrics_path(format: :json)

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "serves download metrics breakdown JSON for curators" do
    sign_in_as(email: "curator-breakdown@example.edu", name: "Curator Breakdown", role: "curator")

    get download_metrics_breakdown_metrics_path(format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("application/json")

    parsed = JSON.parse(response.body)
    expect(parsed).to include("generated_at", "summary", "calendar_years", "fiscal_years")
  end

  it "returns filtered yearly totals in download metrics breakdown JSON" do
    sign_in_as(email: "admin-breakdown-filtered@example.edu", name: "Admin Breakdown", role: "admin")

    public_dataset = create(:dataset, :published, key: "IDB-BRK-PUB", identifier: "10.5555/BRK-PUB", embargo: Dataset::EMBARGO_NONE)
    hidden_dataset = create(:dataset, :published, key: "IDB-BRK-HID", identifier: "10.5555/BRK-HID", embargo: Dataset::EMBARGO_FILE, release_date: Date.current + 45)

    DatasetDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, download_date: Date.new(2025, 7, 15), tally: 6)
    DatasetDownloadTally.create!(dataset_key: hidden_dataset.key, doi: hidden_dataset.identifier, download_date: Date.new(2025, 7, 15), tally: 10)

    FileDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, file_web_id: "brk01", filename: "public.tsv", download_date: Date.new(2025, 7, 15), tally: 4)
    FileDownloadTally.create!(dataset_key: hidden_dataset.key, doi: hidden_dataset.identifier, file_web_id: "brk02", filename: "hidden.tsv", download_date: Date.new(2025, 7, 15), tally: 8)

    get download_metrics_breakdown_metrics_path(format: :json)

    expect(response).to have_http_status(:ok)
    parsed = JSON.parse(response.body)

    expect(parsed.dig("summary", "dataset", "all_time")).to eq(6)
    expect(parsed.dig("summary", "datafile", "all_time")).to eq(4)

    calendar_2025 = parsed.fetch("calendar_years").find { |row| row["year_label"] == "2025" }
    expect(calendar_2025).to include("dataset_downloads" => 6, "datafile_downloads" => 4)

    fiscal_2025 = parsed.fetch("fiscal_years").find { |row| row["fiscal_year_label"] == "FY25" }
    expect(fiscal_2025).to include("dataset_downloads" => 6, "datafile_downloads" => 4)
  end

  it "includes public external-file datasets in breakdown totals" do
    sign_in_as(email: "admin-external-breakdown@example.edu", name: "Admin External Breakdown", role: "admin")

    external_dataset = create(
      :dataset,
      :published,
      key: "IDB-EXT-BRK",
      identifier: "10.5555/EXT-BRK",
      embargo: Dataset::EMBARGO_NONE,
      external_files_note: "Files are hosted in external storage",
      external_files_link: "https://example.edu/external/files"
    )

    DatasetDownloadTally.create!(dataset_key: external_dataset.key, doi: external_dataset.identifier, download_date: Date.new(2026, 2, 10), tally: 5)

    get download_metrics_breakdown_metrics_path(format: :json)

    expect(response).to have_http_status(:ok)
    parsed = JSON.parse(response.body)

    expect(parsed.dig("summary", "dataset", "all_time")).to eq(5)
    calendar_2026 = parsed.fetch("calendar_years").find { |row| row["year_label"] == "2026" }
    expect(calendar_2026).to include("dataset_downloads" => 5)
  end

  it "renders calendar and fiscal yearly totals on dedicated download metrics page" do
    sign_in_as(email: "admin-metrics-yearly@example.edu", name: "Admin Metrics Yearly", role: "admin")

    public_dataset = create(:dataset, :published, key: "IDB-YEAR-PUB", identifier: "10.5555/YEAR-PUB", embargo: Dataset::EMBARGO_NONE)
    hidden_dataset = create(:dataset, :published, key: "IDB-YEAR-HID", identifier: "10.5555/YEAR-HID", embargo: Dataset::EMBARGO_METADATA, release_date: Date.current + 90)

    DatasetDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, download_date: Date.new(2025, 8, 1), tally: 4)
    DatasetDownloadTally.create!(dataset_key: hidden_dataset.key, doi: hidden_dataset.identifier, download_date: Date.new(2025, 8, 1), tally: 12)
    FileDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, file_web_id: "yr01", filename: "pub.csv", download_date: Date.new(2025, 8, 1), tally: 2)
    FileDownloadTally.create!(dataset_key: hidden_dataset.key, doi: hidden_dataset.identifier, file_web_id: "yr02", filename: "hid.csv", download_date: Date.new(2025, 8, 1), tally: 9)

    get curator_download_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("2025")
    expect(response.body).to include("FY25")
    expect(response.body).to match(/<td>2025<\/td>\s*<td>4<\/td>\s*<td>2<\/td>/)
    expect(response.body).to match(/<td>FY25<\/td>\s*<td>2025-07-01 to 2026-06-30<\/td>\s*<td>4<\/td>\s*<td>2<\/td>/)
  end

  it "shows download metrics summary with calendar and fiscal totals" do
    sign_in_as(email: "admin-summary@example.edu", name: "Admin Summary", role: "admin")

    public_dataset = create(:dataset, :published, key: "IDB-SUM-PUB", identifier: "10.5555/SUM-PUB", embargo: Dataset::EMBARGO_NONE)
    hidden_dataset = create(:dataset, :published, key: "IDB-SUM-HID", identifier: "10.5555/SUM-HID", embargo: Dataset::EMBARGO_FILE, release_date: Date.current + 60)

    DatasetDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, download_date: Date.current, tally: 5)
    DatasetDownloadTally.create!(dataset_key: hidden_dataset.key, doi: hidden_dataset.identifier, download_date: Date.current, tally: 11)

    FileDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, file_web_id: "sum01", filename: "public.csv", download_date: Date.current, tally: 3)
    FileDownloadTally.create!(dataset_key: hidden_dataset.key, doi: hidden_dataset.identifier, file_web_id: "sum02", filename: "hidden.csv", download_date: Date.current, tally: 7)

    get admin_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Download Metrics Summary")
    expect(response.body).to include("Dataset downloads")
    expect(response.body).to include("Datafile downloads")
    expect(response.body).to include("Calendar #{Date.current.year}")
    expect(response.body).to include("FY#{format('%02d', (Date.current.month >= 7 ? Date.current.year : Date.current.year - 1) % 100)}")
    expect(response.body).to match(/<td>Dataset downloads<\/td>\s*<td>5<\/td>\s*<td>5<\/td>\s*<td>5<\/td>/)
    expect(response.body).to match(/<td>Datafile downloads<\/td>\s*<td>3<\/td>\s*<td>3<\/td>\s*<td>3<\/td>/)
  end

  it "serves admin metrics for curators" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    get admin_metrics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Metrics exports")
    expect(response.body).not_to include("Regenerate")
  end

  it "blocks refresh actions for non-admin users" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor", role: "depositor")

    post refresh_dataset_downloads_metrics_path

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "enqueues refresh actions for admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect do
      post refresh_dataset_downloads_metrics_path
    end.to have_enqueued_job(MetricRefreshJob).with(:dataset_downloads_json)

    expect(response).to redirect_to(metrics_path)
  end

  it "blocks refresh actions for curators" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    expect do
      post refresh_dataset_downloads_metrics_path
    end.not_to have_enqueued_job(MetricRefreshJob)

    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("not authorized")
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

    file_download_scope = DayFileDownload.where(file_web_id: datafile.web_id)
    file_tally_before = FileDownloadTally.find_by(file_web_id: datafile.web_id)&.tally.to_i
    dataset_tally_before = DatasetDownloadTally.find_by(dataset_key: dataset.key)&.tally.to_i

    expect do
      get download_dataset_datafile_path(dataset, datafile)
    end.to change { file_download_scope.count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)&.tally).to eq(file_tally_before + 1)
    expect(DatasetDownloadTally.find_by(dataset_key: dataset.key)&.tally).to eq(dataset_tally_before + 1)
  end

  it "does not enqueue a refresh when the metric is already in progress" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")
    allow(Metric).to receive(:in_progress?).with(:dataset_downloads_json).and_return(true)

    expect do
      post refresh_dataset_downloads_metrics_path
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

    post refresh_funders_csv_metrics_path

    expect(Metric).to have_received(:clear_in_progress).with(:funders_csv)
    expect(Rails.logger).to have_received(:error).with(/Unable to enqueue metric refresh for funders_csv: queue unavailable/)
    expect(response).to redirect_to(metrics_path)
    expect(flash[:alert]).to include("Unable to start Funders CSV refresh right now")
  end

  it "enqueues the remaining refresh actions for admins" do
    sign_in_as(email: "admin2@example.edu", name: "Admin User Two", role: "admin")

    expect do
      post refresh_datafile_downloads_metrics_path
      post refresh_datasets_tsv_metrics_path
      post refresh_datafiles_csv_metrics_path
      post refresh_container_csv_metrics_path
      post refresh_related_materials_csv_metrics_path
      post refresh_container_contents_csv_metrics_path
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
