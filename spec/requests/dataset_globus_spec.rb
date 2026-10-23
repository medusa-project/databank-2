require "rails_helper"

RSpec.describe "Dataset Globus workflows", type: :request do
  let!(:dataset) do
    Dataset.create!(
      title: "Globus Dataset",
      description: "Files available through Globus",
      owner_uid: "owner@example.edu",
      depositor_name: "Owner",
      depositor_email: "owner@example.edu",
      identifier: "10.5555/IDB-GLOBUS",
      publication_state: :published,
      all_globus: true
    )
  end
  let!(:datafile) { dataset.datafiles.create!(binary_name: "notes.csv", binary_size: 123) }

  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  before do
    allow(IdbConfig).to receive(:fetch).and_call_original
    allow(IdbConfig).to receive(:fetch).with(:globus, :download_url_base)
      .and_return("https://app.globus.org/file-manager?origin_id=download&origin_path=%2F")
  end

  it "renders a Globus link for a public single-file dataset" do
    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("a[href='#{open_in_globus_dataset_path(dataset)}']")).to be_present
  end

  it "shows the pending Globus notice only above the configured size threshold" do
    dataset.update!(all_globus: false)
    datafile.update!(binary_size: 2 * (2**30))
    get dataset_path(dataset)
    expect(response.body).not_to include("not yet available through Globus")

    datafile.update!(binary_size: datafile.binary_size + 1)
    get dataset_path(dataset)
    expect(response.body).to include("not yet available through Globus")
  end

  it "redirects a public visitor to File Manager and records each file download" do
    get open_in_globus_dataset_path(dataset)

    expect(response).to have_http_status(:redirect)
    uri = URI(response.location)
    expect(uri.host).to eq("app.globus.org")
    expect(URI.decode_www_form(uri.query).to_h["origin_path"]).to eq("/#{dataset.key}")
    expect(datafile.total_downloads).to eq(1)
    expect(dataset.total_downloads).to eq(1)
  end

  it "does not redirect to Globus when copies are not ready" do
    dataset.update!(all_globus: false)
    get open_in_globus_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    expect(flash[:alert]).to include("not currently available")
    expect(datafile.total_downloads).to eq(0)
  end

  it "does not expose public Globus downloads to an owner during a file embargo" do
    dataset.update!(embargo: Dataset::EMBARGO_FILE, release_date: Date.tomorrow)
    sign_in_as("depositor", dataset.depositor_email)
    get open_in_globus_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    expect(flash[:alert]).to include("not currently available")
    get dataset_path(dataset)
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{open_in_globus_dataset_path(dataset)}']")).to be_nil
  end

  it "does not expose suppressed files to guests" do
    dataset.update!(hold_state: Dataset::HOLD_PERM_FILE)
    get open_in_globus_dataset_path(dataset)

    expect(response).to redirect_to(root_path)
    expect(datafile.total_downloads).to eq(0)
  end

  it "requires authentication for draft downloads" do
    dataset.update!(publication_state: :draft)
    get open_in_globus_dataset_path(dataset)

    expect(response).to redirect_to(login_path)
  end

  it "reports a missing File Manager configuration without recording downloads" do
    allow(IdbConfig).to receive(:fetch).with(:globus, :download_url_base).and_return("")
    get open_in_globus_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    expect(flash[:alert]).to include("not configured correctly")
    expect(datafile.total_downloads).to eq(0)
  end

  describe "curator import" do
    let(:root) { instance_double("MedusaStorage::Root", root_type: :s3) }

    before do
      dataset.update!(publication_state: :draft)
      allow(StorageManager.instance).to receive(:globus_ingest_root).and_return(root)
      allow(root).to receive(:exist?).with("#{dataset.key}/").and_return(true)
      allow(root).to receive(:file_keys).with(dataset.key).and_return([ "#{dataset.key}/new.csv" ])
      allow(root).to receive(:size).with("#{dataset.key}/new.csv").and_return(256)
    end

    it "shows curator controls associated with a separate POST form" do
      sign_in_as("curator")
      get edit_dataset_path(dataset)

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("button[form='globus-import-form']").text).to eq("Import from Globus")
      expect(doc.at_css("form#globus-import-form")["action"]).to eq(import_from_globus_dataset_path(dataset))
      expect(doc.at_css("form#globus-import-form")["method"]).to eq("post")
      expect(doc.css("form form")).to be_empty
    end

    it "does not show curator import controls to depositors" do
      sign_in_as("depositor", dataset.depositor_email)
      get edit_dataset_path(dataset)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("globus-import-form")
    end

    it "imports files and skips existing filenames on repeated imports" do
      sign_in_as("curator")
      post import_from_globus_dataset_path(dataset, format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["created"]).to eq(1)
      imported = dataset.datafiles.find_by!(binary_name: "new.csv")
      expect(imported.binary_size).to eq(256)
      expect(imported.content_type).to eq("text/csv")

      post import_from_globus_dataset_path(dataset, format: :json)
      expect(response.parsed_body["created"]).to eq(0)
      expect(response.parsed_body["skipped_existing"]).to eq(1)
    end

    it "imports from an S3 prefix without a directory marker" do
      sign_in_as("curator")
      allow(root).to receive(:exist?).and_return(false)
      post import_from_globus_dataset_path(dataset, format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["created"]).to eq(1)
    end

    it "redirects HTML imports back to editing with a summary" do
      sign_in_as("curator")
      post import_from_globus_dataset_path(dataset)

      expect(response).to redirect_to(edit_dataset_path(dataset))
      expect(flash[:notice]).to include("Imported 1 file(s)")
    end

    it "reports a missing ingest directory" do
      sign_in_as("curator")
      allow(root).to receive(:exist?).and_return(false)
      allow(root).to receive(:file_keys).and_return([])
      post import_from_globus_dataset_path(dataset, format: :json)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("Could not import")
    end

    it "returns an error for partial imports rather than reporting success" do
      sign_in_as("curator")
      allow(root).to receive(:file_keys).and_return([ "#{dataset.key}/new.csv", "#{dataset.key}/broken.csv" ])
      allow(root).to receive(:size).with("#{dataset.key}/broken.csv").and_raise(IOError, "storage failed")
      post import_from_globus_dataset_path(dataset, format: :json)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.values_at("created", "failed")).to eq([ 1, 1 ])
    end

    it "does not allow a depositor to import from Globus" do
      sign_in_as("depositor", dataset.depositor_email)
      expect(root).not_to receive(:file_keys)
      post import_from_globus_dataset_path(dataset)

      expect(response).to redirect_to(root_path)
    end

    it "does not allow guests to import" do
      post import_from_globus_dataset_path(dataset)
      expect(response).to redirect_to(login_path)
    end

    it "preserves legacy curator imports into published datasets" do
      sign_in_as("curator")
      dataset.update!(publication_state: :published)
      post import_from_globus_dataset_path(dataset, format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["created"]).to eq(1)
      expect(dataset.reload.all_globus).to be false
    end
  end

  def sign_in_as(role, email = "curator@example.edu")
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer", uid: email,
      info: { email: email, name: "Globus User", nickname: email, role: role }
    )
    get "/auth/developer/callback"
    expect(response).to have_http_status(:redirect)
  end
end
