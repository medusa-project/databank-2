class MetricsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[
    index
    datafiles_simple_list
    datafiles_csv
    funders_csv
    archived_content_csv
    related_materials_csv
  ]

  before_action :require_admin_or_curator!, only: %i[
    admin_metrics
    download_metrics
    dataset_downloads_csv
    datafile_downloads_csv
    archived_download_metric
    download_zip
  ]

  before_action :require_admin!, only: %i[
    refresh_datasets_tsv
    refresh_datafiles_csv
    refresh_container_csv
    refresh_funders_csv
    refresh_related_materials_csv
    refresh_container_contents_csv
  ]

  def index
    serve_metrics_file(Rails.root.join("public/metrics_dashboard.html"), type: "text/html")
  end

  def admin_metrics
    @metric_definitions = Metric.admin_definitions
    @modified_times = Metric.modified_times
    @refresh_status = Metric.refresh_status
    @title = "Curator Metrics"
  end

  def download_metrics
    begin
      Metric.ensure_download_metrics
    rescue StandardError => error
      Rails.logger.error("Unable to ensure download metrics: #{error.message}")
      flash.now[:alert] = "Some download metrics files are temporarily unavailable."
    end

    assign_download_metric_years
    @title = "Download Metrics"
  end

  def dataset_downloads_csv
    filename = Metric.filename_for_year_metric(:dataset_downloads, Metric.current_calendar_year, :calendar)
    serve_metrics_file(Rails.root.join("public", filename), type: "text/csv")
  end

  def datafile_downloads_csv
    filename = Metric.filename_for_year_metric(:datafile_downloads, Metric.current_calendar_year, :calendar)
    serve_metrics_file(Rails.root.join("public", filename), type: "text/csv")
  end

  def archived_download_metric
    metric_type = params[:metric_type]&.to_sym
    raw_year = params[:year].to_s
    slice_type = params[:slice_type]&.to_sym
    year = raw_year.start_with?("FY") ? raw_year.delete_prefix("FY").to_i : raw_year.to_i

    return head :bad_request unless metric_type.in?(%i[dataset_downloads datafile_downloads])
    return head :bad_request unless slice_type.in?(%i[calendar fiscal])
    return head :bad_request unless year > 1 && year < 2100

    content = Metric.retrieve_archived_metric_from_storage(metric_type, year, slice_type)
    return head :not_found unless content.present?

    send_data(
      content,
      type: "text/csv",
      filename: Metric.filename_for_year_metric(metric_type, year, slice_type),
      disposition: "inline"
    )
  rescue StandardError => error
    Rails.logger.error("Error retrieving archived metric #{metric_type}/#{year}/#{slice_type}: #{error.message}")
    head :internal_server_error
  end

  def download_zip
    group = params[:group].to_sym
    return head :bad_request unless Metric::DOWNLOAD_ZIP_GROUPS.include?(group)

    zip_data = Metric.build_zip_for_group(group)
    send_data zip_data, type: "application/zip", filename: "#{group}_downloads.zip", disposition: "attachment"
  rescue ArgumentError
    head :bad_request
  rescue StandardError => error
    Rails.logger.error("Error building zip for group #{group}: #{error.message}")
    head :internal_server_error
  end

  def datafiles_simple_list
    public_dataset_ids = Dataset.publicly_readable_now.select(:id)
    @datafiles = Datafile.where(dataset_id: public_dataset_ids)

    respond_to do |format|
      format.json
    end
  end

  def datafiles_csv
    serve_configured_metric_file(:datafiles_csv)
  end

  def funders_csv
    serve_configured_metric_file(:funders_csv)
  end

  def archived_content_csv
    serve_metrics_file(Rails.root.join("public/archive_file_contents.csv"), type: "text/csv")
  end

  def related_materials_csv
    serve_configured_metric_file(:related_materials_csv)
  end

  def assign_download_metric_years
    @download_metrics_availability = Metrics::DownloadMetricsAvailability.new
    @current_calendar_year = @download_metrics_availability.current_calendar_year
    @current_fiscal_year = @download_metrics_availability.current_fiscal_year
  end

  def refresh_datasets_tsv
    enqueue_metric_refresh(metric_key: :datasets_tsv, label: "Datasets TSV")
  end

  def refresh_datafiles_csv
    enqueue_metric_refresh(metric_key: :datafiles_csv, label: "Datafiles CSV")
  end

  def refresh_container_csv
    enqueue_metric_refresh(metric_key: :container_contents_csv, label: "Container contents CSV")
  end

  def refresh_funders_csv
    enqueue_metric_refresh(metric_key: :funders_csv, label: "Funders CSV")
  end

  def refresh_related_materials_csv
    enqueue_metric_refresh(metric_key: :related_materials_csv, label: "Related materials CSV")
  end

  def refresh_container_contents_csv
    enqueue_metric_refresh(metric_key: :container_contents_csv, label: "Container contents CSV")
  end

  private

  def refresh_path_for(metric_key)
    {
      datasets_tsv: refresh_datasets_tsv_metrics_path,
      datafiles_csv: refresh_datafiles_csv_metrics_path,
      container_contents_csv: refresh_container_contents_csv_metrics_path,
      funders_csv: refresh_funders_csv_metrics_path,
      related_materials_csv: refresh_related_materials_csv_metrics_path
    }.fetch(metric_key.to_sym)
  end

  helper_method :refresh_path_for

  def enqueue_metric_refresh(metric_key:, label:)
    if Metric.in_progress?(metric_key)
      redirect_to metrics_path, alert: "#{label} refresh is already in progress. Please refresh the page to check status."
      return
    end

    begin
      Metric.set_in_progress(metric_key)
      MetricRefreshJob.perform_later(metric_key)
      redirect_to metrics_path, notice: "#{label} refresh started. Please refresh this page manually to check for an updated status."
    rescue StandardError => error
      Metric.clear_in_progress(metric_key)
      Rails.logger.error("Unable to enqueue metric refresh for #{metric_key}: #{error.message}")
      redirect_to metrics_path, alert: "Unable to start #{label} refresh right now. Please try again."
    end
  end

  def serve_metrics_file(path, type:)
    file_path = path.to_s
    return head :not_found unless File.file?(file_path)

    send_file file_path, type: type, disposition: "inline"
  end

  def serve_configured_metric_file(metric_key)
    definition = Metric.definition_for(metric_key)
    serve_metrics_file(definition.relative_path, type: definition.content_type)
  end

  def require_admin_or_curator!
    return if current_user&.admin? || current_user&.curator?

    redirect_to metrics_path, alert: "You are not authorized to perform this action."
  end

  def require_admin!
    return if current_user&.admin?

    redirect_to metrics_path, alert: "You are not authorized to perform this action."
  end

end
