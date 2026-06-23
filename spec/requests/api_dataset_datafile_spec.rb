require "rails_helper"

RSpec.describe "API dataset datafile upload", type: :request do
  let(:dataset) do
    Dataset.create!(
      title: "API upload dataset",
      description: "Dataset for token-authenticated upload tests",
      owner_uid: "owner-api-1",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu"
    )
  end
  let(:token) { dataset.new_token.identifier }
  let(:path) { "/api/dataset/#{dataset.key}/datafile" }

  before do
    allow(StorageManager.instance.draft_root).to receive(:copy_io_to).and_return(true)
  end

  it "uploads a file with a valid token" do
    post path,
      params: {
        binary: uploaded_file("test,data\n1,2\n"),
        description: "CLI upload"
      },
      headers: { "Authorization" => "Token token=#{token}" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("file has been successfully uploaded to draft server")

    datafile = dataset.datafiles.order(:created_at).last
    expect(datafile).to be_present
    expect(datafile.storage_root).to eq(StorageManager.instance.draft_root.name)
    expect(datafile.binary_name).to eq("upload.csv")
  end

  it "accepts tus metadata registration" do
    upload_id = TusUploadStore.create(upload_length: 42)
    TusUploadStore.new(upload_id).append_chunk!(expected_offset: 0, chunk_io: StringIO.new("x" * 42))

    post path,
      params: {
        tus_url: "https://example.edu/files/#{upload_id}",
        filename: "via-tus.csv",
        size: 42
      },
      headers: { "Authorization" => "Token token=#{token}" }

    expect(response).to have_http_status(:ok)
    datafile = dataset.datafiles.order(:created_at).last
    expect(datafile.binary_name).to eq("via-tus.csv")
    expect(datafile.binary_size).to eq(42)
    expect(datafile.storage_key).to include(upload_id)
  end

  it "returns bad request for an invalid tus reference" do
    post path,
      params: {
        tus_url: "https://example.edu/files/not-a-uuid",
        filename: "via-tus.csv",
        size: 42
      },
      headers: { "Authorization" => "Token token=#{token}" }

    expect(response).to have_http_status(:bad_request)
    expect(response.body).to include("Invalid TUS upload reference")
  end

  it "returns bad credentials for an invalid token" do
    post path,
      params: { binary: uploaded_file("a,b\n") },
      headers: { "Authorization" => "Token token=invalid" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to include("Bad credentials")
  end

  it "returns not found for non-draft datasets" do
    dataset.update!(publication_state: :published, identifier: "10.9999/IDB-0000001")

    post path,
      params: { binary: uploaded_file("a,b\n") },
      headers: { "Authorization" => "Token token=#{token}" }

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Dataset Not Found")
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
