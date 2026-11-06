class TusFilesController < ApplicationController
  TUS_VERSION = "1.0.0".freeze

  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  before_action :authenticate_token_request!
  before_action :set_tus_headers

  def create
    upload_length = read_header("Upload-Length")
    render_invalid_upload_length and return if upload_length.blank?

    upload_id = TusUploadStore.create(
      upload_length: upload_length, metadata: parse_upload_metadata, dataset_key: @token.dataset_key
    )
    response.set_header("Location", "#{request.base_url}/files/#{upload_id}")
    response.set_header("Upload-Offset", "0")
    head :created
  rescue ArgumentError, TusUploadStore::InvalidUpload
    render_invalid_upload_length
  end

  def update
    store = TusUploadStore.new(params[:id])
    expected_offset = read_header("Upload-Offset")
    render_invalid_offset and return if expected_offset.blank?
    if request.media_type != "application/offset+octet-stream"
      render plain: "Invalid Content-Type", status: :unsupported_media_type
      return
    end

    new_offset = store.with_lock do
      store.append_chunk!(
        dataset_key: @token.dataset_key, expected_offset: expected_offset,
        chunk_io: request.body, content_length: request.content_length
      )
    end
    response.set_header("Upload-Offset", new_offset.to_s)
    head :no_content
  rescue TusUploadStore::OffsetMismatch
    render plain: "Upload offset mismatch", status: :conflict
  rescue TusUploadStore::InvalidUploadId, TusUploadStore::UploadNotFound
    render_not_found
  rescue ArgumentError, TypeError, TusUploadStore::InvalidUpload
    render plain: "Invalid upload chunk or offset", status: :bad_request
  end

  def show
    store = TusUploadStore.new(params[:id])
    current = store.with_lock { store.state(dataset_key: @token.dataset_key) }
    response.set_header("Upload-Offset", current.fetch("Upload-Offset"))
    response.set_header("Upload-Length", current.fetch("Upload-Length"))
    response.set_header("Cache-Control", "no-store")
    head :ok
  rescue TusUploadStore::InvalidUploadId, TusUploadStore::UploadNotFound
    render_not_found
  end

  def options
    response.set_header("Tus-Version", TUS_VERSION)
    response.set_header("Tus-Extension", "creation")
    response.set_header("Tus-Max-Size", TusUploadStore::MAX_UPLOAD_SIZE.to_s)
    head :no_content
  end

  private

  def authenticate_token_request!
    token_identifier = ActionController::HttpAuthentication::Token.token_and_options(request)&.first
    @token = Token.find_by(identifier: token_identifier) if token_identifier.present?
    return if @token.present?

    response.headers["WWW-Authenticate"] = "Token realm=\"Application\""
    render json: "Bad credentials", status: :unauthorized
  end

  def set_tus_headers
    response.set_header("Tus-Resumable", TUS_VERSION)
  end

  def parse_upload_metadata
    raw = read_header("Upload-Metadata").to_s
    return {} if raw.blank?

    raw.split(",").each_with_object({}) do |pair, result|
      key, value = pair.strip.split(" ", 2)
      next if key.blank?

      result[key] = value.present? ? Base64.decode64(value) : ""
    end
  end

  def read_header(name)
    request.headers[name] || request.headers["HTTP_#{name.upcase.tr('-', '_')}"]
  end

  def render_not_found
    render plain: "Not Found", status: :not_found
  end

  def render_invalid_upload_length
    render plain: "Upload-Length is required", status: :bad_request
  end

  def render_invalid_offset
    render plain: "Upload-Offset is required", status: :bad_request
  end
end
