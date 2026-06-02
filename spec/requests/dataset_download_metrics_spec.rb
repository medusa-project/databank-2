require "rails_helper"

RSpec.describe "Dataset download metrics", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "returns download metrics json for a public published dataset" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/IDB-METRICS"
    )
    datafile = create(:datafile, dataset: dataset, binary_name: "analysis.csv", binary_size: 2048)

    DatasetDownloadTally.create!(dataset_key: dataset.key, doi: dataset.identifier, download_date: Date.current, tally: 3)
    FileDownloadTally.create!(dataset_key: dataset.key, doi: dataset.identifier, file_web_id: datafile.web_id, filename: datafile.binary_name, download_date: Date.current, tally: 2)

    get download_metrics_dataset_path(dataset, format: :json)

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)

    expect(payload).to include("dataset_downloads")
    metrics = payload.fetch("dataset_downloads")
    expect(metrics["doi"]).to eq("10.5555/IDB-METRICS")
    expect(metrics["dataset_total_downloads"]).to eq(3)
    expect(metrics["files"]).to include(a_hash_including("filename" => "analysis.csv", "file_total_downloads" => 2))
  end

  it "requires sign in for a non-public draft dataset" do
    dataset = create(:dataset, publication_state: :draft)

    get download_metrics_dataset_path(dataset, format: :json)

    expect(response).to redirect_to(login_path)
  end
end
