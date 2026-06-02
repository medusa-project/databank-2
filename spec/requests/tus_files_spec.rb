require "rails_helper"

RSpec.describe "TUS files endpoint", type: :request do
  let(:token) { Token.create!(dataset_key: "IDB-12345", identifier: Token.generate_auth_token) }

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
        "Upload-Length" => "11"
      }
    upload_path = URI.parse(response.headers.fetch("Location")).path

    patch upload_path,
      params: "hello ",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Offset" => "0",
        "Content-Type" => "application/offset+octet-stream"
      }
    expect(response).to have_http_status(:no_content)
    expect(response.headers["Upload-Offset"]).to eq("6")

    patch upload_path,
      params: "world",
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0",
        "Upload-Offset" => "6",
        "Content-Type" => "application/offset+octet-stream"
      }
    expect(response).to have_http_status(:no_content)
    expect(response.headers["Upload-Offset"]).to eq("11")

    head upload_path,
      headers: {
        "Authorization" => "Token token=#{token.identifier}",
        "Tus-Resumable" => "1.0.0"
      }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Upload-Offset"]).to eq("11")
    expect(response.headers["Upload-Length"]).to eq("11")
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
end
