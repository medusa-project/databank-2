class DatafilesController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[download view]

  before_action :set_dataset
  before_action :set_datafile, only: %i[update destroy download view]

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

  def view
    unless can?(:view_files, @dataset)
      if !logged_in? && !@dataset.publicly_readable_now?
        redirect_to(root_path, alert: "You are not authorized to perform this action.")
      else
        head :forbidden
      end
      return
    end

    # For text files: render inline
    if @datafile.text?
      render_text_preview
      return
    end

    # For PDFs: redirect to viewer route or serve with inline disposition
    if @datafile.pdf?
      render_pdf_preview
      return
    end

    # For images: render image view
    if @datafile.image?
      render_image_preview
      return
    end

    # For Microsoft files: redirect to Office365 viewer
    if @datafile.microsoft?
      redirect_to microsoft_preview_url(@datafile), allow_other_host: true
      return
    end

    # For unsupported file types: redirect to download
    redirect_to download_dataset_datafile_path(@dataset, @datafile), notice: "Preview not available for this file type. Downloading instead."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :update, @dataset unless %w[download view].include?(action_name)
  end

  def set_datafile
    @datafile = @dataset.datafiles.find_by!(web_id: params[:web_id])
  end

  def datafile_params
    params.require(:datafile).permit(:binary_name, :binary_size, :description, :binary, :storage_root, :storage_key, :medusa_id, :position, :row_position)
  end

  def render_text_preview
    @text_content = if @datafile.binary.attached?
                      @datafile.binary.download.force_encoding("UTF-8")
    elsif @datafile.exists_on_storage?
                      @datafile.with_input_io do |io|
                        io.read.force_encoding("UTF-8")
                      end
    else
                      "(Preview not available)"
    end

    render :text_preview
  rescue Encoding::InvalidByteSequenceError
    render :text_preview, locals: { error: "File contains invalid UTF-8 characters and cannot be displayed" }
  end

  def render_pdf_preview
    set_datafile
    if @datafile.binary.attached?
      send_data(
        @datafile.binary.download,
        filename: @datafile.binary.filename.to_s,
        disposition: :inline,
        type: "application/pdf"
      )
    elsif @datafile.exists_on_storage?
      @datafile.with_input_io do |io|
        send_data(
          io.read,
          filename: (@datafile.binary_name.presence || @datafile.web_id),
          disposition: :inline,
          type: "application/pdf"
        )
      end
    else
      head :not_found
    end
  end

  def render_image_preview
    set_datafile
    if @datafile.binary.attached?
      send_data(
        @datafile.binary.download,
        filename: @datafile.binary.filename.to_s,
        disposition: :inline,
        type: @datafile.binary.content_type
      )
    elsif @datafile.exists_on_storage?
      @datafile.with_input_io do |io|
        send_data(
          io.read,
          filename: (@datafile.binary_name.presence || @datafile.web_id),
          disposition: :inline,
          type: @datafile.content_type
        )
      end
    else
      head :not_found
    end
  end

  def microsoft_preview_url(datafile)
    return "" unless datafile.binary.attached?

    file_url = url_for(datafile.binary)
    "https://view.officeapps.live.com/op/view.aspx?src=#{ERB::Util.url_encode(file_url)}"
  end
end
