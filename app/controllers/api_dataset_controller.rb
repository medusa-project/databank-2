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
  rescue StandardError
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
    datafile = @dataset.datafiles.build(
      binary_name: params.require(:filename),
      binary_size: params.require(:size),
      description: params[:description].presence,
      storage_root: StorageManager.instance.draft_root.name
    )
    datafile.valid?
    datafile.storage_key = storage_key_for_tus(datafile)
    store = persist_tus_upload_to_storage!(datafile)
    datafile.save!
    store.delete!
  end

  def persist_tus_upload_to_storage!(datafile)
    tus_id = tus_upload_id
    raise ArgumentError, "Missing tus upload identifier" if tus_id.blank?

    store = TusUploadStore.new(tus_id)
    store.with_input_io do |io|
      StorageManager.instance.draft_root.copy_io_to(datafile.storage_key, io, nil, datafile.binary_size.to_i)
    end
    store
  end

  def tus_upload_id
    tus_path = URI.parse(params[:tus_url]).path
    tus_path.to_s.split("/").reject(&:blank?).last
  rescue URI::InvalidURIError
    nil
  end

  def storage_key_for_tus(datafile)
    tus_id = tus_upload_id
    return File.join(datafile.web_id, datafile.binary_name) if tus_id.blank?

    File.join("tus", tus_id, datafile.binary_name)
  rescue URI::InvalidURIError
    File.join(datafile.web_id, datafile.binary_name)
  end

  def render_unauthorized
    response.headers["WWW-Authenticate"] = "Token realm=\"Application\""
    render json: "Bad credentials", status: :unauthorized
  end

  def render_dataset_not_found
    render json: "Dataset Not Found", status: :not_found
  end
end
