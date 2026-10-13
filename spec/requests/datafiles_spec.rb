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
      peek_type: Datafile::PeekType::ALL_TEXT,
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
      peek_type: Datafile::PeekType::MARKDOWN,
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
      peek_type: Datafile::PeekType::PART_TEXT,
      peek_content: "truncated preview lines"
    )

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("truncated preview lines")
  end

  it "renders archive preview page from peek_content" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(
      :datafile,
      dataset: dataset,
      attach_binary: false,
      peek_type: Datafile::PeekType::LISTING,
      peek_content: "<div class='indent'>archive/from-peek.txt</div>"
    )

    datafile.nested_items.create!(
      item_name: "folder",
      item_path: "folder",
      media_type: "inode/directory",
      is_directory: true
    )

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Archive Contents")
    expect(response.body).to include("archive/from-peek.txt")
  end

  it "renders archive preview from peek_content when nested items are absent" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    datafile = create(
      :datafile,
      dataset: dataset,
      attach_binary: false,
      peek_type: Datafile::PeekType::LISTING,
      peek_content: "<div class='indent'>legacy-entry.txt</div>"
    )

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Archive Contents")
    expect(response.body).to include("legacy-entry.txt")
    expect(response.body).not_to include("No items to display")
  end

  it "renders PDF preview inline" do
    sign_in_as(email: owner_email, name: "Owner User", role: "depositor")
    published_dataset = create(
      :dataset,
      :published,
      depositor_email: owner_email,
      identifier: "10.5555/pdf-view-count"
    )
    datafile = create(:datafile, dataset: published_dataset, peek_type: Datafile::PeekType::PDF)

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
    datafile = create(:datafile, dataset: published_dataset, peek_type: Datafile::PeekType::IMAGE)

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
    datafile = create(:datafile, dataset: published_dataset, peek_type: Datafile::PeekType::MICROSOFT)

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
      peek_type: Datafile::PeekType::ALL_TEXT,
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
      peek_type: Datafile::PeekType::LISTING,
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
    datafile = create(:datafile, dataset: dataset, peek_type: Datafile::PeekType::NONE)

    get view_dataset_datafile_path(dataset, datafile)

    expect(response).to redirect_to(download_dataset_datafile_path(dataset, datafile))
    expect(flash[:notice]).to eq("Preview not available for this file type. Downloading instead.")
  end

  describe "bulk uploads" do
    before { sign_in_as(email: owner_email, name: "Owner User", role: "depositor") }

    it "rejects a request without files" do
      expect do
        post bulk_create_dataset_datafiles_path(dataset)
      end.not_to change(Datafile, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "No files were selected for upload.")
    end

    [ 1, 2 ].each do |count|
      it "uploads #{count} files with exact counts and synchronized metadata" do
        files = count.times.map { |n| uploaded_file("row #{n}\n", filename: "file-#{n}.csv") }

        expect do
          post bulk_create_dataset_datafiles_path(dataset), params: { datafiles: files }
        end.to change { dataset.datafiles.count }.by(count)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to eq(
          "success" => true, "count" => count,
          "message" => "Uploaded #{count} file#{count == 1 ? '' : 's'} successfully."
        )
        dataset.datafiles.order(:binary_name).each_with_index do |datafile, n|
          expect(datafile.binary_name).to eq("file-#{n}.csv")
          expect(datafile.binary_size).to eq("row #{n}\n".bytesize)
          expect(datafile.binary.download).to eq("row #{n}\n")
        end
      end
    end

    it "reports partial failure while retaining the successful upload" do
      allow_any_instance_of(Datafile).to receive(:save).and_wrap_original do |original, *args|
        if original.receiver.binary_name == "bad.csv"
          original.receiver.errors.add(:binary, "is invalid")
          false
        else
          original.call(*args)
        end
      end

      expect do
        post bulk_create_dataset_datafiles_path(dataset), params: {
          datafiles: [
            uploaded_file("good\n", filename: "good.csv"),
            uploaded_file("bad\n", filename: "bad.csv")
          ]
        }
      end.to change { dataset.datafiles.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "success" => false,
        "message" => "Uploaded 1 file, but 1 failed.",
        "errors" => [ "bad.csv: Binary is invalid" ]
      )
      expect(dataset.datafiles.pluck(:binary_name)).to eq([ "good.csv" ])
    end
  end

  describe "bulk removal" do
    before { sign_in_as(email: owner_email, name: "Owner User", role: "depositor") }

    it "does not remove files when the selection is empty or blank" do
      datafile = create(:datafile, dataset: dataset)

      expect do
        post bulk_destroy_dataset_datafiles_path(dataset), params: { selected_files: [ "", " " ] }
      end.not_to change(Datafile, :count)

      expect(response).to redirect_to(edit_dataset_path(dataset))
      expect(flash[:alert]).to eq("No files were selected for removal.")
      expect(datafile.reload).to be_persisted
    end

    it "removes only selected files belonging to the dataset" do
      selected = create(:datafile, dataset: dataset)
      retained = create(:datafile, dataset: dataset)
      foreign = create(:datafile)

      expect do
        post bulk_destroy_dataset_datafiles_path(dataset), params: {
          selected_files: [ selected.web_id, selected.web_id, foreign.web_id, "missing", "" ]
        }
      end.to change(Datafile, :count).by(-1)

      expect(response).to redirect_to(edit_dataset_path(dataset))
      expect(flash[:notice]).to eq("Removed 1 file metadata entry.")
      expect(dataset.datafiles.reload).to contain_exactly(retained)
      expect(foreign.reload).to be_persisted
    end

    it "accepts a scalar file ID" do
      datafile = create(:datafile, dataset: dataset)

      expect do
        post bulk_destroy_dataset_datafiles_path(dataset), params: { selected_files: datafile.web_id }
      end.to change(Datafile, :count).by(-1)

      expect(flash[:notice]).to eq("Removed 1 file metadata entry.")
    end

    it "reports the number of files removed for multiple selections" do
      files = create_list(:datafile, 2, dataset: dataset)

      expect do
        post bulk_destroy_dataset_datafiles_path(dataset), params: { selected_files: files.map(&:web_id) }
      end.to change(Datafile, :count).by(-2)

      expect(flash[:notice]).to eq("Removed 2 file metadata entries.")
    end
  end

  describe "access boundaries" do
    it "redirects a guest away from a private preview without reading or counting content" do
      datafile = create(:datafile, dataset: dataset)
      expect_any_instance_of(Datafile).not_to receive(:record_download)
      expect_any_instance_of(Datafile).not_to receive(:with_input_io)

      get view_dataset_datafile_path(dataset, datafile)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "forbids a guest preview of embargoed files" do
      embargoed = create(:dataset, :published, :embargo_file_unreleased)
      datafile = create(:datafile, dataset: embargoed)
      expect_any_instance_of(Datafile).not_to receive(:record_download)

      get view_dataset_datafile_path(embargoed, datafile)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to be_blank
    end

    it "forbids a signed-in non-owner's private preview" do
      datafile = create(:datafile, dataset: dataset)
      sign_in_as(email: "viewer@example.edu", name: "Viewer User", role: "depositor")

      get view_dataset_datafile_path(dataset, datafile)

      expect(response).to have_http_status(:forbidden)
    end

    it "prevents a non-owner from uploading or removing files in bulk" do
      datafile = create(:datafile, dataset: dataset)
      sign_in_as(email: "viewer@example.edu", name: "Viewer User", role: "depositor")

      expect do
        post bulk_create_dataset_datafiles_path(dataset), params: { datafiles: [ uploaded_file("blocked\n") ] }
      end.not_to change(Datafile, :count)
      expect(response).to redirect_to(root_path)

      expect do
        post bulk_destroy_dataset_datafiles_path(dataset), params: { selected_files: [ datafile.web_id ] }
      end.not_to change(Datafile, :count)
      expect(response).to redirect_to(root_path)
    end

    it "does not resolve another dataset's file through the requested dataset" do
      foreign = create(:datafile)
      sign_in_as(email: owner_email, name: "Owner User", role: "depositor")

      get view_dataset_datafile_path(dataset, foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "file index" do
    it "lists the dataset's files sorted by name for a curator" do
      sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")
      create(:datafile, dataset: dataset, attach_binary: false, binary_name: "z-last.csv")
      create(:datafile, dataset: dataset, attach_binary: false, binary_name: "a-first.csv")
      foreign = create(:datafile, attach_binary: false, binary_name: "foreign.csv")

      get dataset_datafiles_path(dataset)

      expect(response).to have_http_status(:ok)
      names = Nokogiri::HTML(response.body).css("input[name='datafile[binary_name]']").map { |input| input["value"] }
      expect(names).to eq(%w[a-first.csv z-last.csv])
      expect(response.body).not_to include(foreign.web_id)
    end
  end

  describe "uncached previews" do
    before { sign_in_as(email: owner_email, name: "Owner User", role: "depositor") }

    it "renders attachment text when persisted preview content is absent" do
      datafile = create(:datafile, dataset: dataset, peek_type: Datafile::PeekType::ALL_TEXT)
      datafile.update_columns(peek_content: nil)

      get view_dataset_datafile_path(dataset, datafile)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("column_a,column_b")
    end

    it "reads uncached text from MedusaStorage and escapes HTML" do
      datafile = create(:datafile, dataset: dataset, attach_binary: false,
        binary_name: "notes.txt", peek_type: Datafile::PeekType::ALL_TEXT,
        storage_root: "medusa", storage_key: "notes.txt")
      root = instance_double(StorageManager.instance.medusa_root.class)
      allow(StorageManager.instance.root_set).to receive(:at).with("medusa").and_return(root)
      allow(root).to receive(:exist?).with("notes.txt").and_return(true)
      allow(root).to receive(:with_input_io).with("notes.txt").and_yield(StringIO.new("<script>alert('x')</script>notes"))

      get view_dataset_datafile_path(dataset, datafile)

      expect(response).to have_http_status(:ok)
      preview = Nokogiri::HTML(response.body).at_css(".dataset-text-content")
      expect(preview.text).to eq("<script>alert('x')</script>notes")
      expect(preview.css("script")).to be_empty
      expect(root).to have_received(:with_input_io).with("notes.txt")
    end

    it "shows the unavailable text preview message when no binary exists" do
      datafile = create(:datafile, dataset: dataset, attach_binary: false, peek_type: Datafile::PeekType::ALL_TEXT)

      get view_dataset_datafile_path(dataset, datafile)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("(Preview not available)")
    end

    it "shows an explicit warning when reading a text preview raises an encoding error" do
      datafile = create(:datafile, dataset: dataset, attach_binary: false,
        peek_type: Datafile::PeekType::ALL_TEXT, storage_root: "medusa", storage_key: "invalid.txt")
      root = instance_double(StorageManager.instance.medusa_root.class)
      io = instance_double(StringIO)
      allow(StorageManager.instance.root_set).to receive(:at).with("medusa").and_return(root)
      allow(root).to receive(:exist?).with("invalid.txt").and_return(true)
      allow(root).to receive(:with_input_io).with("invalid.txt").and_yield(io)
      allow(io).to receive(:read).and_raise(Encoding::InvalidByteSequenceError, "invalid byte sequence")

      get view_dataset_datafile_path(dataset, datafile)

      expect(response).to have_http_status(:ok)
      warning = Nokogiri::HTML(response.body).at_css("[role='alert']")
      expect(warning.text).to include("File contains invalid UTF-8 characters and cannot be displayed")
    end

    {
      Datafile::PeekType::PDF => [ "report.pdf", "application/pdf", "%PDF-1.7 preview" ],
      Datafile::PeekType::IMAGE => [ "figure.png", "image/png", "image bytes" ]
    }.each do |peek_type, (filename, content_type, content)|
      it "serves a storage-backed #{peek_type} inline with its filename and MIME type" do
        datafile = create(:datafile, dataset: dataset, attach_binary: false,
          binary_name: filename, peek_type: peek_type, storage_root: "medusa", storage_key: filename)
        root = instance_double(StorageManager.instance.medusa_root.class)
        allow(StorageManager.instance.root_set).to receive(:at).with("medusa").and_return(root)
        allow(root).to receive(:exist?).with(filename).and_return(true)
        allow(root).to receive(:with_input_io).with(filename).and_yield(StringIO.new(content))

        get view_dataset_datafile_path(dataset, datafile)

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(content)
        expect(response.headers["Content-Type"]).to include(content_type)
        expect(response.headers["Content-Disposition"]).to include("inline", filename)
        expect(root).to have_received(:with_input_io).with(filename)
      end

      it "returns not found for a #{peek_type} without a binary" do
        datafile = create(:datafile, dataset: dataset, attach_binary: false,
          binary_name: filename, peek_type: peek_type)

        get view_dataset_datafile_path(dataset, datafile)

        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_blank
      end
    end

    it "sanitizes archive listings without preserving interactive or executable markup" do
      datafile = create(:datafile, dataset: dataset, attach_binary: false,
        peek_type: Datafile::PeekType::LISTING,
        peek_content: '<div class="indent" onclick="alert(1)">file.txt<script>alert(1)</script><a href="https://example.test">link</a></div>')

      get view_dataset_datafile_path(dataset, datafile)

      expect(response).to have_http_status(:ok)
      listing = Nokogiri::HTML(response.body).at_css(".idb-archive-legacy-listing")
      expect(listing.text).to include("file.txt")
      expect(listing.at_css("div")["class"]).to eq("indent")
      expect(listing.css("script, a, [onclick]")).to be_empty
    end
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

  def uploaded_file(contents, filename: "upload.csv")
    file = Tempfile.new([ "upload", ".csv" ])
    file.write(contents)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: filename)
  ensure
    file&.close
  end
end
