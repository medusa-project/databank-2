require "rails_helper"

RSpec.describe "Tus S3 integration", type: :request do
  it "stores multipart chunks and registers the S3 object without a local copy", if: ENV["TUS_S3_INTEGRATION"] == "true" do
    configured = StorageManager.instance.draft_root
    root = MedusaStorage::Root::S3.new(
      name: "draft", bucket: configured.bucket, region: configured.region,
      endpoint: configured.endpoint, aws_access_key_id: configured.aws_access_key_id,
      aws_secret_access_key: configured.aws_secret_access_key,
      force_path_style: configured.force_path_style,
      prefix: "#{configured.prefix}tus-spec-#{SecureRandom.hex(8)}/"
    )
    allow(StorageManager.instance).to receive(:draft_root).and_return(root)
    allow(StorageManager.instance.root_set).to receive(:at).with("draft").and_return(root)
    dataset = Dataset.create!(
      title: "Tus S3", description: "Integration", owner_uid: "tus-s3",
      depositor_name: "Test", depositor_email: "test@example.edu"
    )
    token = dataset.create_token!(identifier: Token.generate_auth_token)
    headers = { "Authorization" => "Token token=#{token.identifier}", "Tus-Resumable" => "1.0.0" }
    chunk = "a" * (5 * 1024**2)
    upload_id = nil

    begin
      post "/files", headers: headers.merge("Upload-Length" => (chunk.bytesize + 5).to_s)
      expect(response).to have_http_status(:created)
      location = response.headers.fetch("Location")
      path = URI.parse(location).path
      upload_id = path.split("/").last
      patch path, params: chunk, headers: headers.merge(
        "Upload-Offset" => "0", "Content-Type" => "application/offset+octet-stream"
      )
      expect(response).to have_http_status(:no_content)
      expect(response.headers["Upload-Offset"]).to eq(chunk.bytesize.to_s)
      patch path, params: "final", headers: headers.merge(
        "Upload-Offset" => chunk.bytesize.to_s, "Content-Type" => "application/offset+octet-stream"
      )
      expect(response).to have_http_status(:no_content)
      expect(root.s3_object("tus/#{upload_id}").get.body.read).to eq(chunk + "final")

      post "/api/dataset/#{dataset.key}/datafile",
        params: { tus_url: location, filename: "test.bin", size: chunk.bytesize + 5 },
        headers: headers
      expect(response).to have_http_status(:ok)
      datafile = dataset.datafiles.find_by!(binary_name: "test.bin")
      expect(datafile.storage_key).to eq("tus/#{upload_id}")
      expect(root.s3_object("tus/#{upload_id}.info")).not_to exist
    ensure
      if upload_id
        store = TusUploadStore.new(upload_id)
        begin
          info = store.storage.read_info(upload_id)
          store.storage.delete_file(upload_id, info)
        rescue Tus::NotFound
          root.s3_object("tus/#{upload_id}").delete
        end
      end
    end
  end
end
