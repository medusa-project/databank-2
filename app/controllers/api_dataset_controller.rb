class ApiDatasetController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[datafile]
  skip_before_action :verify_authenticity_token, only: %i[datafile]

  before_action :set_dataset
  before_action :authenticate_token_request!

  def datafile
    if params[:tus_url].present?
      create_from_tus_metadata!
    else
      create_from_binary_upload!
    end

    render json: "file has been successfully uploaded to draft server"
  rescue TusUploadStore::UploadNotFound, TusUploadStore::InvalidUploadId, TusUploadStore::InvalidUpload, ArgumentError
    render json: "Invalid TUS upload reference", status: :bad_request
  rescue StandardError => e
    Rails.logger.error("Failed to store dataset upload: #{e.class}: #{e.message}")
    render json: "Encountered error while storing file on draft server", status: :internal_server_error
  end

  private

  def set_dataset
    @dataset = Dataset.find_by(key: params[:dataset_key])
    render_dataset_not_found and return if @dataset.blank? || !@dataset.draft?
  end

  def authenticate_token_request!
    token_identifier = ActionController::HttpAuthentication::Token.token_and_options(request)&.first
    render_unauthorized and return if token_identifier.blank?

    dataset_token = @dataset.current_token
    return if dataset_token&.identifier == token_identifier

    render_unauthorized
  end

  def create_from_binary_upload!
    uploaded_io = params.require(:binary)
    datafile = @dataset.datafiles.build(
      binary_name: uploaded_io.original_filename,
      binary_size: uploaded_io.size,
      description: params[:description].presence,
      storage_root: StorageManager.instance.draft_root.name
    )
    datafile.valid?
    datafile.storage_key = File.join(datafile.web_id, datafile.binary_name)
    StorageManager.instance.draft_root.copy_io_to(datafile.storage_key, uploaded_io, nil, uploaded_io.size)
    datafile.save!
  end

  def create_from_tus_metadata!
    store = TusUploadStore.new(tus_upload_id)
    store.with_lock do
      info = store.state(dataset_key: @dataset.key)
      size = Integer(params.require(:size), 10)
      raise TusUploadStore::InvalidUpload unless size == Integer(info.fetch("Upload-Length"), 10)
      raise TusUploadStore::InvalidUpload unless info.fetch("Upload-Offset") == info.fetch("Upload-Length")
      object = store.storage.bucket.object(store.object_key)
      raise TusUploadStore::InvalidUpload unless object.exists? && object.content_length == size

      name = params.require(:filename)
      existing = Datafile.find_by(storage_root: StorageManager.instance.draft_root.name, storage_key: store.storage_key)
      if existing
        raise TusUploadStore::InvalidUpload unless existing.dataset_id == @dataset.id &&
          existing.binary_name == name && existing.binary_size == size
      else
        @dataset.datafiles.create!(
          binary_name: name,
          binary_size: size,
          description: params[:description].presence,
          storage_root: StorageManager.instance.draft_root.name,
          storage_key: store.storage_key
        )
      end
    end
    store.remove_info!
  end

  def tus_upload_id
    tus_path = URI.parse(params[:tus_url]).path
    tus_path.to_s.split("/").reject(&:blank?).last
  rescue URI::InvalidURIError
    nil
  end

  def render_unauthorized
    response.headers["WWW-Authenticate"] = "Token realm=\"Application\""
    render json: "Bad credentials", status: :unauthorized
  end

  def render_dataset_not_found
    render json: "Dataset Not Found", status: :not_found
  end
end
