require "rails_helper"

RSpec.describe "Dataset external files", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "shows external files note and access link on dataset show" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/EXTSHOW",
      external_files_note: "Files are available in an external repository.",
      external_files_link: "https://example.org/granite/collection"
    )

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Files - Subset")
    expect(response.body).to include("Files - All")
    expect(response.body).to include("Files are available in an external repository.")
    expect(response.body).to include("Access All Files")
  end

  it "treats link-only datasets as external files" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/EXTLINK",
      external_files_note: "",
      external_files_link: "https://example.org/granite/link-only"
    )

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Files - Subset")
    expect(response.body).to include("Access All Files")
  end

  it "redirects to external files and records download tallies" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/EXTREDIRECT",
      external_files_link: "https://example.org/granite/download"
    )
    create(:datafile, dataset: dataset)
    file_count = dataset.datafiles.count

    expect do
      get open_in_granite_dataset_path(dataset)
    end.to change(DayFileDownload, :count).by(file_count)
      .and change(DatasetDownloadTally, :count).by(1)
      .and change(FileDownloadTally, :count).by(file_count)

    expect(response).to redirect_to("https://example.org/granite/download")
  end

  it "returns to dataset page when no external files link is present" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/NOLINK",
      external_files_note: "External source exists",
      external_files_link: nil
    )

    get open_in_granite_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("No external files link is available for this dataset.")
  end

  it "returns to dataset page when external files link uses an unsafe scheme" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/BADSCHEME",
      external_files_link: "javascript:alert('xss')"
    )
    create(:datafile, dataset: dataset)

    expect do
      get open_in_granite_dataset_path(dataset)
    end.to change(DayFileDownload, :count).by(0)
      .and change(DatasetDownloadTally, :count).by(0)
      .and change(FileDownloadTally, :count).by(0)

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("The external files link is not a valid URL.")
  end

  it "returns to dataset page when external files link is malformed" do
    dataset = create(
      :dataset,
      :published,
      embargo: Dataset::EMBARGO_NONE,
      identifier: "10.5555/BADMALFORMED",
      external_files_link: "https://example .org/bad"
    )
    create(:datafile, dataset: dataset)

    expect do
      get open_in_granite_dataset_path(dataset)
    end.to change(DayFileDownload, :count).by(0)
      .and change(DatasetDownloadTally, :count).by(0)
      .and change(FileDownloadTally, :count).by(0)

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("The external files link is not a valid URL.")
  end
end
