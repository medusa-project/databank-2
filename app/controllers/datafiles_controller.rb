class DatafilesController < ApplicationController
  skip_before_action :authenticate_user!, only: :download

  before_action :set_dataset
  before_action :set_datafile, only: %i[update destroy download]

  def create
    @datafile = @dataset.datafiles.build(datafile_params)
    @datafile.sync_metadata_from_attachment!

    if @datafile.save
      redirect_to edit_dataset_path(@dataset), notice: "File metadata added."
    else
      redirect_to edit_dataset_path(@dataset), alert: @datafile.errors.full_messages.to_sentence
    end
  end

  def update
    @datafile.assign_attributes(datafile_params)
    @datafile.sync_metadata_from_attachment!

    if @datafile.save
      redirect_to edit_dataset_path(@dataset), notice: "File metadata updated."
    else
      redirect_to edit_dataset_path(@dataset), alert: @datafile.errors.full_messages.to_sentence
    end
  end

  def destroy
    @datafile.destroy!
    redirect_to edit_dataset_path(@dataset), notice: "File metadata removed."
  end

  def download
    unless can?(:view_files, @dataset)
      if !logged_in? && !@dataset.publicly_readable_now?
        redirect_to(root_path, alert: "You are not authorized to perform this action.")
      else
        head :forbidden
      end
      return
    end

    @datafile.record_download(request.remote_ip)

    if @datafile.binary.attached?
      send_data(
        @datafile.binary.download,
        filename: @datafile.binary.filename.to_s,
        disposition: :attachment,
        type: @datafile.binary.content_type
      )
    elsif @datafile.exists_on_storage?
      @datafile.with_input_io do |io|
        send_data(
          io.read,
          filename: (@datafile.binary_name.presence || @datafile.web_id),
          disposition: :attachment,
          type: "application/octet-stream"
        )
      end
    else
      filename = @datafile.binary_name.presence || "#{@datafile.web_id}.txt"
      send_data(
        "Download placeholder for #{@datafile.web_id} (#{filename})",
        filename: filename,
        disposition: :attachment,
        type: "text/plain"
      )
    end
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :update, @dataset unless action_name == "download"
  end

  def set_datafile
    @datafile = @dataset.datafiles.find_by!(web_id: params[:web_id])
  end

  def datafile_params
    params.require(:datafile).permit(:binary_name, :binary_size, :description, :binary, :storage_root, :storage_key, :medusa_id, :position, :row_position)
  end
end
