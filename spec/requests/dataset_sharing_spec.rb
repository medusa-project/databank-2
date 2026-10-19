require "rails_helper"

RSpec.describe "Private dataset sharing", type: :request do
  let(:dataset) { create(:dataset) }
  let(:code) { dataset.create_share_code!.code }

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
      info: { email: email, name: "Test User", nickname: email, role: role }
    )
    get "/auth/developer/callback"
    expect(response).to have_http_status(:redirect)
  end

  it "generates and reuses the same sharing link for an owner" do
    sign_in_as(email: dataset.depositor_email)

    post share_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
    link = JSON.parse(response.body).fetch("private_share_link")
    expect(link).to end_with("/datasets/#{dataset.key}?code=#{dataset.reload.current_share_code}")

    expect { post share_dataset_path(dataset), as: :json }.not_to change(ShareCode, :count)
    expect(JSON.parse(response.body)).to eq("private_share_link" => link)
  end

  it "redirects HTML generation to the dataset with expiry and access information" do
    sign_in_as(email: dataset.depositor_email)

    post share_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("12 months", "Anybody with this link")
  end

  it "allows editors and curators to generate links" do
    create(:creator, dataset: dataset, email: "editor@example.edu")
    sign_in_as(email: "editor@example.edu")
    post share_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)

    sign_in_as(email: "curator@example.edu", role: "curator")
    delete remove_sharing_link_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
    post share_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
  end

  it "allows an explicit edit-access grantee to generate links" do
    DatasetAccessGrant.create!(dataset: dataset, email: "grantee@example.edu", access_level: :editor)
    sign_in_as(email: "grantee@example.edu")

    post share_dataset_path(dataset), as: :json

    expect(response).to have_http_status(:ok)
    expect(dataset.reload.current_share_code).to be_present
  end

  it "blocks unrelated users from creating or revoking codes" do
    code
    sign_in_as(email: "other@example.edu")

    expect { post share_dataset_path(dataset), as: :json }.not_to change(ShareCode, :count)
    expect(response).to redirect_to(root_path)
    expect { delete remove_sharing_link_dataset_path(dataset), as: :json }.not_to change(ShareCode, :count)
    expect(response).to redirect_to(root_path)
  end

  it "requires authentication to manage links even with a valid share code" do
    post share_dataset_path(dataset), params: { code: code }, as: :json
    expect(response).to redirect_to(login_path)
    delete remove_sharing_link_dataset_path(dataset), params: { code: code }, as: :json
    expect(response).to redirect_to(login_path)
    expect(dataset.reload.share_code).to be_present
  end

  it "allows a guest to read a draft and includes code-bearing preview and download links" do
    datafile = create(:datafile, dataset: dataset)

    get dataset_path(dataset), params: { code: code }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dataset.title)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("a[href='#{download_dataset_datafile_path(dataset, datafile, code: code)}']")).to be_present
    expect(document.at_css("a[href='#{view_dataset_datafile_path(dataset, datafile, code: code)}']")).to be_present
    expect(response.body).not_to include("Generate private sharing link", "Delete sharing link", "Edit")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "allows an unrelated signed-in user to read but not edit with a code" do
    sign_in_as(email: "reader@example.edu")
    get dataset_path(dataset), params: { code: code }
    expect(response).to have_http_status(:ok)

    patch dataset_path(dataset), params: { code: code, dataset: { title: "Not permitted" } }
    expect(response).to redirect_to(root_path)
    expect(dataset.reload.title).not_to eq("Not permitted")
  end

  it "does not retain sharing permission after a code-bearing request" do
    get dataset_path(dataset), params: { code: code }
    expect(response).to have_http_status(:ok)

    get dataset_path(dataset)
    expect(response).to redirect_to(login_path)
  end

  it "does not expose a privately shared dataset in public search" do
    get dataset_path(dataset), params: { code: code }
    expect(response).to have_http_status(:ok)

    get datasets_path, params: { q: dataset.title }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(dataset_path(dataset))
  end

  it "rejects wrong, blank and array codes" do
    code
    [ "wrong", "", [ code ] ].each do |invalid|
      get dataset_path(dataset), params: { code: invalid }
      expect(response).to redirect_to(login_path)
    end
  end

  it "rejects expired codes and regenerates them for editors" do
    expired = dataset.create_share_code!(created_at: 1.year.ago - 1.day).code
    get dataset_path(dataset), params: { code: expired }
    expect(response).to redirect_to(login_path)

    sign_in_as(email: dataset.depositor_email)
    post share_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
    expect(dataset.reload.current_share_code).not_to eq(expired)
  end

  it "rejects a different dataset's code" do
    other = create(:dataset)
    get dataset_path(other), params: { code: code }
    expect(response).to redirect_to(login_path)
  end

  it "downloads and previews files with the code and preserves it in preview navigation" do
    datafile = create(:datafile, dataset: dataset, binary_name: "notes.txt", peek_content: "Shared preview")

    get download_dataset_datafile_path(dataset, datafile), params: { code: code }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("attachment")

    get view_dataset_datafile_path(dataset, datafile), params: { code: code }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shared preview")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("a[href='#{download_dataset_datafile_path(dataset, datafile, code: code)}']")).to be_present
    expect(document.at_css("a[href='#{dataset_path(dataset, code: code)}']")).to be_present
  end

  it "does not grant access to another dataset's files" do
    other = create(:dataset)
    datafile = create(:datafile, dataset: other)

    get download_dataset_datafile_path(other, datafile), params: { code: code }
    expect(response).to redirect_to(root_path)
  end

  it "preserves shared access in an unsupported preview's download redirect" do
    datafile = create(:datafile, dataset: dataset, binary_name: "raw.unknown", attach_binary: false)

    get view_dataset_datafile_path(dataset, datafile), params: { code: code }

    expect(response).to redirect_to(download_dataset_datafile_path(dataset, datafile, code: code))
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "preserves shared access to the external-files endpoint" do
    dataset.update!(external_files_link: "https://example.edu/files")

    get dataset_path(dataset), params: { code: code }
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("a[href='#{open_in_granite_dataset_path(dataset, code: code)}']")).to be_present

    get open_in_granite_dataset_path(dataset), params: { code: code }
    expect(response).to redirect_to("https://example.edu/files")
  end

  [ Dataset::HOLD_TEMP_FILE, Dataset::HOLD_TEMP_METADATA, Dataset::HOLD_TEMP_VERSION ].each do |hold|
    it "allows a valid code to read metadata and files during #{hold}" do
      dataset.update!(hold_state: hold)
      datafile = create(:datafile, dataset: dataset)

      get dataset_path(dataset), params: { code: code }
      expect(response).to have_http_status(:ok)
      get download_dataset_datafile_path(dataset, datafile), params: { code: code }
      expect(response).to have_http_status(:ok)
    end
  end

  [ Dataset::EMBARGO_FILE, Dataset::EMBARGO_METADATA ].each do |embargo|
    it "allows shared access to #{embargo}-embargoed metadata and files" do
      dataset.update!(publication_state: :published, embargo: embargo, release_date: Date.current + 30)
      datafile = create(:datafile, dataset: dataset)

      get dataset_path(dataset), params: { code: code }
      expect(response).to have_http_status(:ok)
      get download_dataset_datafile_path(dataset, datafile), params: { code: code }
      expect(response).to have_http_status(:ok)
    end
  end

  it "preserves the share code in aggregate download requests" do
    dataset.update!(
      identifier: "10.5555/SHARING", all_medusa: true,
      publication_state: :published, embargo: Dataset::EMBARGO_FILE, release_date: Date.current + 30
    )
    files = create_list(:datafile, 2, dataset: dataset)
    allow(DownloaderClient).to receive(:datafiles_download_hash).and_return(
      status: "ok", download_url: "https://download.example.edu/bundle.zip", total_size: 100
    )

    get dataset_path(dataset), params: { code: code }
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    form = document.at_css("#custom-download-form")
    expect(form["data-custom-downloader-url-value"]).to eq(download_link_dataset_path(dataset, code: code))

    get download_link_dataset_path(dataset), params: { code: code, web_ids: files.map(&:web_id).join("~") }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("status" => "ok", "url" => "https://download.example.edu/bundle.zip")
  end

  it "revokes a link immediately and generates a different replacement" do
    old_code = code
    sign_in_as(email: dataset.depositor_email)
    delete remove_sharing_link_dataset_path(dataset), as: :json
    expect(response).to have_http_status(:ok)
    expect(dataset.reload.share_code).to be_nil

    delete logout_path
    get dataset_path(dataset), params: { code: old_code }
    expect(response).to redirect_to(login_path)

    sign_in_as(email: dataset.depositor_email)
    post share_dataset_path(dataset), as: :json
    expect(dataset.reload.current_share_code).not_to eq(old_code)
  end

  it "reports generation failures instead of returning a successful link" do
    sign_in_as(email: dataset.depositor_email)
    allow_any_instance_of(Dataset).to receive(:create_share_code!).and_raise(ActiveRecord::RecordInvalid.new(ShareCode.new))
    allow(Rails.logger).to receive(:warn)

    post share_dataset_path(dataset), as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)).to include("private_share_link" => nil, "error" => "Error generating share link.")
    expect(Rails.logger).to have_received(:warn).with(/Error generating sharing link/)
  end

  it "reports an error when there is no link to remove" do
    sign_in_as(email: dataset.depositor_email)
    delete remove_sharing_link_dataset_path(dataset), as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)).to include("error" => "Unexpected Error")
  end

  it "does not generate a sharing link for a public dataset" do
    dataset.update!(publication_state: :published)
    sign_in_as(email: dataset.depositor_email)

    expect { post share_dataset_path(dataset), as: :json }.not_to change(ShareCode, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders a sharing badge only for an effective share code, never an upload token" do
    dataset.create_token!(identifier: "upload-only-token")
    sign_in_as(email: dataset.depositor_email)

    get datasets_path
    expect(response.body).not_to include("has sharing link")

    code
    get datasets_path
    expect(response.body).to include("has sharing link")

    dataset.share_code.update!(created_at: 2.years.ago)
    get datasets_path
    expect(response.body).not_to include("has sharing link")
  end

  it "provides labeled, readonly sharing controls only to editors" do
    code
    sign_in_as(email: dataset.depositor_email)
    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("label[for='sharing-link']")).to be_present
    expect(document.at_css("#sharing-link[readonly]")["value"]).to eq(dataset.sharing_link)
    expect(document.at_css("#sharing-copy-status[role='status']")).to be_present
    expect(document.at_css("form[action='#{remove_sharing_link_dataset_path(dataset)}'] button")).to be_present
  end
end
