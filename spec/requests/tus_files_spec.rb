require "rails_helper"
require_relative "../support/fake_tus_storage"

RSpec.describe "TUS files endpoint", type: :request do
  let(:dataset) do
    Dataset.create!(
      key: "IDB-12345",
      title: "TUS upload dataset",
      description: "Dataset for TUS upload tests",
      owner_uid: "owner-tus-1",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu"
    )
  end
  let(:token) { dataset.create_token!(identifier: Token.generate_auth_token) }
  let(:storage) { FakeTusStorage.new }

  before do
    allow_any_instance_of(TusUploadStore).to receive(:storage).and_return(storage)
  end

  it "round-trips upload metadata through Rails JSON" do
    metadata = { "Upload-Length" => "11", "Upload-Offset" => "0" }

    expect(ActiveSupport::JSON.decode(ActiveSupport::JSON.encode(metadata))).to eq(metadata)
  end

  it "creates a tus upload and returns location" do
    post "/files",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Length" => "11"
      }

    expect(response).to have_http_status(:created)
    expect(response.headers["Location"]).to include("/files/")
    expect(response.headers["Tus-Resumable"]).to eq("1.0.0")
    expect(response.headers["Upload-Offset"]).to eq("0")
  end

  it "accepts patch chunks and reports offsets" do
    post "/files",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Length" => (5 * 1024 * 1024 + 5).to_s
      }
    upload_path = URI.parse(response.headers.fetch("Location")).path

    patch upload_path,
      params: "a" * (5 * 1024 * 1024),
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Offset" => "0",
        "Content-Type" => "application/offset+octet-stream"
      }
    expect(response).to have_http_status(:no_content)
    expect(response.headers["Upload-Offset"]).to eq((5 * 1024 * 1024).to_s)

    patch upload_path,
      params: "world",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Offset" => (5 * 1024 * 1024).to_s,
        "Content-Type" => "application/offset+octet-stream"
      }
    expect(response).to have_http_status(:no_content)
    expect(response.headers["Upload-Offset"]).to eq((5 * 1024 * 1024 + 5).to_s)

    head upload_path,
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0"
      }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Upload-Offset"]).to eq((5 * 1024 * 1024 + 5).to_s)
    expect(response.headers["Upload-Length"]).to eq((5 * 1024 * 1024 + 5).to_s)
  end

  it "registers a completed Tus upload in MedusaStorage" do
    Dir.mktmpdir("tus-upload-spec-") do |directory|
      allow(StorageManager.instance).to receive(:tmpdir).and_return(directory)
      expect(StorageManager.instance.draft_root).not_to receive(:copy_io_to)
      headers = { "Authorization" => "Token token=#{token.identifier}", "Tus-Resumable" => "1.0.0" }

      post "/files", headers: headers.merge("Upload-Length" => "11", "Upload-Metadata" => "filename aGVsbG8udHh0")
      expect(response).to have_http_status(:created)
      location = response.headers.fetch("Location")
      upload_path = URI.parse(location).path
      upload_id = upload_path.split("/").last
      store = TusUploadStore.new(upload_id)
      expect(store.state(dataset_key: dataset.key).fetch("metadata")).to eq("filename" => "hello.txt")

      patch upload_path, params: "hello world", headers: headers.merge(
        "Upload-Offset" => "0", "Content-Type" => "application/offset+octet-stream"
      )
      expect(response).to have_http_status(:no_content)
      expect(response.headers["Upload-Offset"]).to eq("11")

      post "/api/dataset/#{dataset.key}/datafile",
        params: { tus_url: location, filename: "hello.txt", size: 11 },
        headers: headers

      expect(response).to have_http_status(:ok)
      datafile = dataset.datafiles.find_by!(binary_name: "hello.txt")
      expect(datafile.binary_size).to eq(11)
      expect(datafile.storage_key).to eq("tus/#{upload_id}")
      expect(storage.objects.fetch(upload_id)).to eq("hello world")
      expect(storage.infos).not_to have_key(upload_id)
      expect(Dir.children(directory)).to be_empty
    end
  end

  it "returns unauthorized without token" do
    post "/files", headers: { "Tus-Resumable" => "1.0.0", "Upload-Length" => "5" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to include("Bad credentials")
  end

  it "returns conflict when offset does not match" do
    post "/files",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Length" => "5"
      }
    upload_path = URI.parse(response.headers.fetch("Location")).path

    patch upload_path,
      params: "abc",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Offset" => "2",
        "Content-Type" => "application/offset+octet-stream"
      }

    expect(response).to have_http_status(:conflict)
  end

  it "returns not found for invalid upload identifiers" do
    head "/files/not-a-uuid",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0"
      }

    expect(response).to have_http_status(:not_found)
  end

  it "enforces the advertised 50 GiB upload limit" do
    headers = { "Authorization" => "Token token=#{token.identifier}", "Tus-Resumable" => "1.0.0" }
    options "/files", headers: headers
    expect(response.headers["Tus-Max-Size"]).to eq((50 * 1024**3).to_s)

    post "/files", headers: headers.merge("Upload-Length" => (50 * 1024**3).to_s)
    expect(response).to have_http_status(:created)
    post "/files", headers: headers.merge("Upload-Length" => (50 * 1024**3 + 1).to_s)
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects undersized non-final chunks" do
    headers = { "Authorization" => "Token token=#{token.identifier}", "Tus-Resumable" => "1.0.0" }
    post "/files", headers: headers.merge("Upload-Length" => (10 * 1024**2).to_s)
    upload_path = URI.parse(response.headers.fetch("Location")).path

    patch upload_path, params: "short", headers: headers.merge(
      "Upload-Offset" => "0", "Content-Type" => "application/offset+octet-stream"
    )
    expect(response).to have_http_status(:bad_request)
    head upload_path, headers: headers
    expect(response.headers["Upload-Offset"]).to eq("0")
  end

  it "rejects chunks over the memory and request-buffering limit" do
    upload_id = TusUploadStore.create(upload_length: (100 * 1024**2).to_s, metadata: {}, dataset_key: dataset.key)
    store = TusUploadStore.new(upload_id)
    expect {
      store.append_chunk!(
        dataset_key: dataset.key, expected_offset: "0", chunk_io: StringIO.new(""),
        content_length: TusUploadStore::MAX_CHUNK_SIZE + 1
      )
    }.to raise_error(TusUploadStore::InvalidUpload)
    expect(store.state(dataset_key: dataset.key).fetch("Upload-Offset")).to eq("0")
  end

  it "recovers if S3 completed an upload before metadata could be saved" do
    upload_id = TusUploadStore.create(upload_length: "5", metadata: {}, dataset_key: dataset.key)
    storage.objects[upload_id] = "hello"
    head "/files/#{upload_id}",
      headers: { "Authorization" => "Token token=#{token.identifier}", "Tus-Resumable" => "1.0.0" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Upload-Offset"]).to eq("5")
    expect(storage.infos.fetch(upload_id)).not_to have_key("multipart_id")
  end

  it "does not allow another dataset's token to access an upload" do
    headers = { "Authorization" => "Token token=#{token.identifier}", "Tus-Resumable" => "1.0.0" }
    post "/files", headers: headers.merge("Upload-Length" => "11")
    upload_path = URI.parse(response.headers.fetch("Location")).path
    other_dataset = Dataset.create!(
      title: "Other", description: "Other dataset", owner_uid: "other",
      depositor_name: "Other", depositor_email: "other@example.edu"
    )
    other_token = other_dataset.create_token!(identifier: Token.generate_auth_token)
    head upload_path, headers: headers.merge("Authorization" => "Token token=#{other_token.identifier}")
    expect(response).to have_http_status(:not_found)
  end
end
