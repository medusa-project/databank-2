require "rails_helper"

RSpec.describe "Dataset file visibility", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  def sign_in_as(email:, role: "depositor")
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer", uid: email,
      info: { email: email, name: "File Visibility User", role: role }
    )
    get "/auth/developer/callback"
  end

  def files_section
    Nokogiri::HTML(response.body).at_css('section[aria-label="Files"]')
  end

  [ Dataset::HOLD_TEMP_FILE, Dataset::HOLD_PERM_FILE ].each do |hold|
    it "replaces the file listing and external links with a message for guests under #{hold}" do
      dataset = create(:dataset, :published, hold_state: hold,
        external_files_link: "https://example.test/restricted-files",
        external_files_note: "Restricted external description")
      datafile = dataset.datafiles.first

      get dataset_path(dataset)

      expect(response).to have_http_status(:ok)
      expect(files_section.text).to include(
        hold == Dataset::HOLD_TEMP_FILE ? "under curator review" : "permanently suppressed"
      )
      expect(files_section.text).not_to include(datafile.binary_name, datafile.description, "Restricted external description")
      expect(files_section.css(".dataset-files-list, .dataset-files-controls, .dataset-external-files")).to be_empty

      get download_dataset_datafile_path(dataset, datafile)
      expect(response).to have_http_status(:forbidden)
      get view_dataset_datafile_path(dataset, datafile)
      expect(response).to have_http_status(:forbidden)
    end
  end

  [
    Dataset::HOLD_TEMP_FILE, Dataset::HOLD_TEMP_METADATA,
    Dataset::HOLD_TEMP_VERSION, Dataset::HOLD_PERM_FILE
  ].each do |hold|
    %w[owner editor creator curator admin].each do |viewer|
      it "keeps file listing and download access for #{viewer} under #{hold}" do
        dataset = create(:dataset, :published, hold_state: hold, depositor_email: "owner-files@example.edu")
        datafile = dataset.datafiles.first
        email = "#{viewer}-files@example.edu"
        DatasetAccessGrant.create!(dataset: dataset, email: email, access_level: :editor) if viewer == "editor"
        create(:creator, dataset: dataset, email: email) if viewer == "creator"
        sign_in_as(email: email, role: %w[curator admin].include?(viewer) ? viewer : "depositor")

        get dataset_path(dataset)

        expect(response).to have_http_status(:ok)
        expect(files_section.css(".dataset-file-item").size).to eq(1)
        expect(files_section.at_css("a[href='#{download_dataset_datafile_path(dataset, datafile)}']")).to be_present
        notice = Nokogiri::HTML(response.body).at_css(".dataset-metadata-restriction-notice")
        if %w[curator admin].include?(viewer)
          expect(notice["role"]).to eq("note")
          expect(notice.text).to include(dataset.visibility, "because you have curator access")
        else
          expect(notice).to be_nil
        end

        get download_dataset_datafile_path(dataset, datafile)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  [ Dataset::HOLD_TEMP_FILE, Dataset::HOLD_TEMP_METADATA, Dataset::HOLD_TEMP_VERSION ].each do |hold|
    it "keeps file access through a valid share link under #{hold}" do
      dataset = create(:dataset, :published, hold_state: hold)
      datafile = dataset.datafiles.first
      code = dataset.create_share_code!.code

      get dataset_path(dataset), params: { code: code }

      expect(response).to have_http_status(:ok)
      expect(files_section.at_css("a[href='#{download_dataset_datafile_path(dataset, datafile, code: code)}']")).to be_present
      get download_dataset_datafile_path(dataset, datafile), params: { code: code }
      expect(response).to have_http_status(:ok)
    end
  end

  %w[owner editor creator curator admin].each do |viewer|
    it "limits permanently metadata-suppressed dataset access for #{viewer} to curators only" do
      dataset = create(:dataset, :published, hold_state: Dataset::HOLD_PERM_METADATA,
        depositor_email: "owner-files@example.edu")
      datafile = dataset.datafiles.first
      email = "#{viewer}-files@example.edu"
      DatasetAccessGrant.create!(dataset: dataset, email: email, access_level: :editor) if viewer == "editor"
      create(:creator, dataset: dataset, email: email) if viewer == "creator"
      sign_in_as(email: email, role: %w[curator admin].include?(viewer) ? viewer : "depositor")
      curator = %w[curator admin].include?(viewer)

      get dataset_path(dataset)
      if curator
        expect(response).to have_http_status(:ok)
        expect(files_section.css(".dataset-file-item").size).to eq(1)
        notice = Nokogiri::HTML(response.body).at_css(".dataset-metadata-restriction-notice")
        expect(notice.text).to include("This dataset has been withdrawn", "available only to curators")
      else
        expect(response).to redirect_to(root_path)
      end
      get download_dataset_datafile_path(dataset, datafile)
      expect(response).to have_http_status(curator ? :ok : :forbidden)
      get view_dataset_datafile_path(dataset, datafile)
      expect(response).to have_http_status(:forbidden) unless curator

      get datasets_path, params: { q: dataset.title }
      if curator
        expect(response.body).to include(dataset_path(dataset))
      else
        expect(response.body).not_to include(dataset_path(dataset))
      end
    end
  end

  [ Dataset::HOLD_PERM_FILE, Dataset::HOLD_PERM_METADATA ].each do |hold|
    it "rejects a residual share code under #{hold}" do
      dataset = create(:dataset, :published, hold_state: hold)
      datafile = dataset.datafiles.first
      code = dataset.create_share_code!.code

      get download_dataset_datafile_path(dataset, datafile), params: { code: code }

      expect(response).not_to have_http_status(:ok)
      get dataset_path(dataset), params: { code: code }
      if hold == Dataset::HOLD_PERM_FILE
        expect(response).to have_http_status(:ok)
        expect(files_section.css(".dataset-files-list")).to be_empty
      else
        expect(response).to redirect_to(login_path)
      end
    end
  end

  it "replaces an active embargoed file listing with a release message" do
    dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_FILE, release_date: Date.current + 10)

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(files_section.text).to include("Files will become available on")
    expect(files_section.css(".dataset-files-list")).to be_empty
  end

  it "shows files without a restriction warning once an embargo is released" do
    dataset = create(:dataset, :published, embargo: Dataset::EMBARGO_FILE, release_date: Date.current)

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(files_section.css(".dataset-file-item").size).to eq(1)
    expect(files_section.text).not_to include("restricted due to embargo")
  end

  it "does not show a curator suppression notice when there is no hold" do
    dataset = create(:dataset, :published)
    sign_in_as(email: "curator-files@example.edu", role: "curator")

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css(".dataset-metadata-restriction-notice")).to be_empty
  end
end
