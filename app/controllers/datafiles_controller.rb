class DatafilesController < ApplicationController
  ArchiveTreeNode = Struct.new(:name, :path, :is_directory, :size, :children, keyword_init: true)

  skip_before_action :authenticate_user!, only: %i[download view]

  before_action :set_dataset
  before_action :set_datafile, only: %i[update destroy download view]

  def index
    authorize! :update, @dataset
    @datafiles = @dataset.datafiles.order(:binary_name)
  end

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

  def bulk_create
    uploaded_files = params.fetch(:datafiles, [])

    if uploaded_files.empty?
      return render json: { error: "No files were selected for upload." }, status: :bad_request
    end

    created = 0
    errors = []

    Array(uploaded_files).each do |file|
      datafile = @dataset.datafiles.build(binary: file, binary_name: file.original_filename)
      datafile.sync_metadata_from_attachment!

      if datafile.save
        created += 1
      else
        errors << "#{file.original_filename}: #{datafile.errors.full_messages.to_sentence}"
      end
    end

    if errors.empty?
      render json: { success: true, message: "Uploaded #{created} file#{created == 1 ? '' : 's'} successfully.", count: created }, status: :created
    else
      render json: { success: false, message: "Uploaded #{created} file#{created == 1 ? '' : 's'}, but #{errors.length} failed.", errors: errors }, status: :ok
    end
  end

  def bulk_destroy
    selected_ids = selected_datafile_ids

    if selected_ids.empty?
      redirect_to edit_dataset_path(@dataset), alert: "No files were selected for removal."
      return
    end

    removed_count = @dataset.datafiles.where(web_id: selected_ids).destroy_all.size
    redirect_to edit_dataset_path(@dataset), notice: "Removed #{removed_count} file metadata entr#{removed_count == 1 ? 'y' : 'ies'}."
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

    # For text and markdown previews, render stored preview content.
    if @datafile.text? || @datafile.markdown?
      render_text_preview
      return
    end

    # For PDFs: redirect to viewer route or serve with inline disposition
    if @datafile.pdf?
      @datafile.record_download(request.remote_ip)
      render_pdf_preview
      return
    end

    # For images: render image view
    if @datafile.image?
      @datafile.record_download(request.remote_ip)
      render_image_preview
      return
    end

    # For Microsoft files: redirect to Office365 viewer
    if @datafile.microsoft?
      @datafile.record_download(request.remote_ip)
      redirect_to microsoft_preview_url(@datafile), allow_other_host: true
      return
    end

    # For archive files: render nested archive listing page
    if @datafile.archive?
      render_archive_preview
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

  def selected_datafile_ids
    ids = params.fetch(:selected_files, [])
    Array(ids).map(&:to_s).reject(&:blank?)
  end

  def render_text_preview
    @text_content = if @datafile.peek_content.present?
                      @datafile.peek_content
    elsif @datafile.binary.attached?
                      @datafile.binary.download.force_encoding("UTF-8")
    elsif @datafile.exists_on_storage?
                      @datafile.with_input_io do |io|
                        io.read.force_encoding("UTF-8")
                      end
    else
                      "(Preview not available)"
    end

    @render_markdown = @datafile.markdown?

    render :text_preview
  rescue Encoding::InvalidByteSequenceError
    render :text_preview, locals: { error: "File contains invalid UTF-8 characters and cannot be displayed" }
  end

  def render_archive_preview
    @archive_listing_html = view_context.sanitize(
      @datafile.peek_content.to_s,
      tags: %w[div span br p ul ol li],
      attributes: %w[class]
    )

    render :archive_preview
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

  def build_archive_tree(nested_items:)
    return [] if nested_items.blank?

    if nested_items.where.not(parent_id: nil).exists?
      build_archive_tree_from_parent_ids(nested_items: nested_items)
    else
      build_archive_tree_from_paths(nested_items: nested_items)
    end
  end

  def build_archive_tree_from_parent_ids(nested_items:)
    node_by_id = {}
    nested_items.each do |item|
      node_by_id[item.id] = ArchiveTreeNode.new(
        name: item.item_name,
        path: item.item_path,
        is_directory: ActiveModel::Type::Boolean.new.cast(item.is_directory),
        size: item.size,
        children: []
      )
    end

    roots = []
    nested_items.each do |item|
      node = node_by_id[item.id]
      parent_node = node_by_id[item.parent_id]
      if parent_node
        parent_node.children << node
      else
        roots << node
      end
    end

    sort_archive_nodes!(nodes: roots)
  end

  def build_archive_tree_from_paths(nested_items:)
    root_map = {}

    nested_items.each do |item|
      path = item.item_path.presence || item.item_name.to_s
      parts = path.split("/").reject(&:blank?)
      next if parts.empty?

      current = root_map
      built_path = []

      parts.each_with_index do |part, index|
        built_path << part
        key = built_path.join("/")
        is_last = index == parts.length - 1

        current[key] ||= ArchiveTreeNode.new(
          name: part,
          path: key,
          is_directory: !is_last,
          size: nil,
          children: {}
        )

        node = current[key]
        if is_last
          node.is_directory = true if ActiveModel::Type::Boolean.new.cast(item.is_directory)
          node.size = item.size if item.size.present?
        end

        current = node.children
      end
    end

    nodes = root_map.values
    finalize_archive_path_nodes!(nodes: nodes)
    sort_archive_nodes!(nodes: nodes)
  end

  def finalize_archive_path_nodes!(nodes:)
    nodes.each do |node|
      if node.children.is_a?(Hash)
        child_nodes = node.children.values
        node.children = child_nodes
      end
      node.is_directory = true if node.children.any?
      finalize_archive_path_nodes!(nodes: node.children)
    end
  end

  def sort_archive_nodes!(nodes:)
    nodes.each { |node| sort_archive_nodes!(nodes: node.children) }

    nodes.sort_by do |node|
      [ node.is_directory ? 0 : 1, node.name.to_s.downcase ]
    end
  end
end
