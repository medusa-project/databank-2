require "rails_helper"

RSpec.describe "Datafiles", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:developer] = nil
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  let(:owner_email) { "owner@example.edu" }
  let(:dataset) { create(:dataset, depositor_email: owner_email, depositor_name: "Owner User") }

  it "creates a datafile and syncs metadata from uploaded attachment" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")

    expect do
      post dataset_datafiles_path(dataset), params: {
        datafile: {
          description: "Codebook CSV",
          binary: uploaded_file("alpha,beta\n1,2\n")
        }
      }
    end.to change { dataset.datafiles.count }.by(1)

    created = dataset.datafiles.order(:created_at).last

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:notice]).to eq("File metadata added.")
    expect(created.description).to eq("Codebook CSV")
    expect(created.binary_name).to eq("upload.csv")
    expect(created.binary_size).to eq("alpha,beta\n1,2\n".bytesize)
  end

  it "redirects with alert when create save fails" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")

    allow_any_instance_of(Datafile).to receive(:save).and_return(false)
    allow_any_instance_of(Datafile).to receive_message_chain(:errors, :full_messages, :to_sentence).and_return("Unable to save file")

    post dataset_datafiles_path(dataset), params: {
      datafile: {
        description: "Broken upload",
        binary: uploaded_file("broken\n")
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:alert]).to eq("Unable to save file")
  end

  it "updates a datafile and re-syncs attachment metadata" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(:datafile, dataset: dataset, description: "Original description")

    patch dataset_datafile_path(dataset, datafile), params: {
      datafile: {
        description: "Updated description",
        binary: uploaded_file("gamma,delta\n3,4\n")
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:notice]).to eq("File metadata updated.")
    expect(datafile.reload.description).to eq("Updated description")
    expect(datafile.binary_name).to eq("upload.csv")
    expect(datafile.binary_size).to eq("gamma,delta\n3,4\n".bytesize)
  end

  it "redirects with alert when update save fails" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(:datafile, dataset: dataset)

    allow_any_instance_of(Datafile).to receive(:save).and_return(false)
    allow_any_instance_of(Datafile).to receive_message_chain(:errors, :full_messages, :to_sentence).and_return("Unable to update file")

    patch dataset_datafile_path(dataset, datafile), params: {
      datafile: {
        description: "Will not persist"
      }
    }

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:alert]).to eq("Unable to update file")
  end

  it "destroys a datafile and redirects back to dataset edit" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(:datafile, dataset: dataset)

    expect do
      delete dataset_datafile_path(dataset, datafile)
    end.to change(Datafile, :count).by(-1)

    expect(response).to redirect_to(edit_dataset_path(dataset))
    expect(flash[:notice]).to eq("File metadata removed.")
  end

  it "redirects guests to root when dataset is not publicly readable" do
    datafile = create(:datafile, dataset: dataset)

    get download_dataset_datafile_path(dataset, datafile)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You are not authorized to perform this action.")
  end

  it "returns forbidden for guests when dataset metadata is public but files are embargoed" do
    embargoed_dataset = create(
      :dataset,
      :published,
      :embargo_file_unreleased,
      depositor_email: owner_email,
      identifier: "10.5555/embargoed-download"
    )
    datafile = create(:datafile, dataset: embargoed_dataset)

    get download_dataset_datafile_path(embargoed_dataset, datafile)

    expect(response).to have_http_status(:forbidden)
    expect(response.body).to be_blank
  end

  it "returns forbidden for signed-in users without file access" do
    datafile = create(:datafile, dataset: dataset)
    sign_in_as(email: "viewer@example.edu", name: "Viewer User", role: "depositor")

    get download_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:forbidden)
  end

  it "downloads attached binary for authorized users and records download" do
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/download-attached"
    )
    datafile = create(:datafile, dataset: published_dataset)

    get download_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.9" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    expect(response.headers["Content-Disposition"]).to include(datafile.binary_name)
    expect(response.body).to include("column_a,column_b")
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)&.tally).to eq(1)
  end

  it "downloads from storage when attachment is absent and storage content exists" do
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/storage-download"
    )
    datafile = create(
      :datafile,
      dataset: published_dataset,
      attach_binary: false,
      binary_name: "stored.bin",
      storage_root: "draft",
      storage_key: "stored/stored.bin"
    )

    allow_any_instance_of(Datafile).to receive(:exists_on_storage?).and_return(true)
    allow_any_instance_of(Datafile).to receive(:with_input_io).and_yield(StringIO.new("stored-binary-content"))

    get download_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.10" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("application/octet-stream")
    expect(response.headers["Content-Disposition"]).to include("stored.bin")
    expect(response.body).to eq("stored-binary-content")
  end

  it "returns placeholder data when neither attachment nor storage content exists" do
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/placeholder-download"
    )
    datafile = create(
      :datafile,
      dataset: published_dataset,
      attach_binary: false,
      binary_name: nil,
      storage_root: "draft",
      storage_key: "missing/file.txt"
    )

    allow_any_instance_of(Datafile).to receive(:exists_on_storage?).and_return(false)

    get download_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.11" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/plain")
    expect(response.headers["Content-Disposition"]).to include("#{datafile.web_id}.txt")
    expect(response.body).to include("Download placeholder for #{datafile.web_id}")
  end

  it "renders text preview from persisted peek content without storage access" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(
      :datafile,
      dataset: dataset,
      attach_binary: false,
      peek_type: "all_text",
      peek_content: "cached preview text"
    )

    expect_any_instance_of(Datafile).not_to receive(:exists_on_storage?)
    expect_any_instance_of(Datafile).not_to receive(:with_input_io)

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("cached preview text")
  end

  it "renders markdown preview content as sanitized HTML" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(
      :datafile,
      dataset: dataset,
      attach_binary: false,
      peek_type: "markdown",
      peek_content: "<h2>Overview</h2><script>alert('x')</script><p>Paragraph</p>"
    )

    expect_any_instance_of(Datafile).not_to receive(:exists_on_storage?)
    expect_any_instance_of(Datafile).not_to receive(:with_input_io)

    get view_dataset_datafile_path(dataset, datafile)

    preview_html = Nokogiri::HTML(response.body).at_css(".dataset-text-content")&.inner_html.to_s

    expect(response).to have_http_status(:ok)
    expect(preview_html).to include("<h2>Overview</h2>")
    expect(preview_html).to include("<p>Paragraph</p>")
    expect(preview_html).not_to include("<script")
  end

  it "renders part_text preview from persisted peek content" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(
      :datafile,
      dataset: dataset,
      attach_binary: false,
      peek_type: "part_text",
      peek_content: "truncated preview lines"
    )

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("truncated preview lines")
  end

  it "renders archive preview page with nested items" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(:datafile, dataset: dataset, attach_binary: false, peek_type: "archive")
    root = datafile.nested_items.create!(
      item_name: "folder",
      item_path: "folder",
      media_type: "inode/directory",
      is_directory: true
    )
    datafile.nested_items.create!(
      item_name: "file.txt",
      item_path: "folder/file.txt",
      media_type: "text/plain",
      size: 25,
      parent: root,
      is_directory: false
    )

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Archive Contents")
    expect(response.body).to include("folder")
    expect(response.body).to include("file.txt")
    expect(response.body).to include("idb-archive-depth-0")
    expect(response.body).to include("idb-archive-depth-1")
    expect(response.body).to include("idb-archive-branch")
  end

  it "renders PDF preview inline" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/pdf-view-count"
    )
    datafile = create(:datafile, dataset: published_dataset, peek_type: "pdf")

    get view_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.12" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("application/pdf")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)&.tally).to eq(1)
  end

  it "renders image preview inline" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/image-view-count"
    )
    datafile = create(:datafile, dataset: published_dataset, peek_type: "image")

    get view_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.13" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)&.tally).to eq(1)
  end

  it "redirects microsoft preview files to Office viewer" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/microsoft-view-count"
    )
    datafile = create(:datafile, dataset: published_dataset, peek_type: "microsoft")

    get view_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.14" }

    expect(response).to have_http_status(:redirect)
    expect(response.headers["Location"]).to include("view.officeapps.live.com")
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)&.tally).to eq(1)
  end

  it "does not count text preview view as a download" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/text-view-no-count"
    )
    datafile = create(
      :datafile,
      dataset: published_dataset,
      attach_binary: false,
      peek_type: "all_text",
      peek_content: "cached preview text"
    )

    get view_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.15" }

    expect(response).to have_http_status(:ok)
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)).to be_nil
  end

  it "does not count archive listing view as a download" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/archive-view-no-count"
    )
    datafile = create(
      :datafile,
      dataset: published_dataset,
      attach_binary: false,
      peek_type: "archive",
      peek_content: "archive listing"
    )
    datafile.nested_items.create!(
      item_name: "folder",
      item_path: "folder",
      media_type: "inode/directory",
      is_directory: true
    )

    get view_dataset_datafile_path(published_dataset, datafile), headers: { "REMOTE_ADDR" => "203.0.113.16" }

    expect(response).to have_http_status(:ok)
    expect(FileDownloadTally.find_by(file_web_id: datafile.web_id)).to be_nil
  end

  it "falls back to download for unsupported peek types" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(:datafile, dataset: dataset, peek_type: "none")

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to redirect_to(download_dataset_datafile_path(dataset, datafile))
    expect(flash[:notice]).to eq("Preview not available for this file type. Downloading instead.")
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
    expect(response).to have_http_status(:redirect)
  end

  def uploaded_file(contents)
    file = Tempfile.new([ "upload", ".csv" ])
    file.write(contents)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "upload.csv")
  ensure
    file&.close
  end
end
