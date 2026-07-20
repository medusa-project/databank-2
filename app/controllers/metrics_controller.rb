class MetricsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[
    index
    dataset_downloads
    file_downloads
    datafiles_simple_list
    datafiles_csv
    funders_csv
    archived_content_csv
    related_materials_csv
  ]

  before_action :require_admin_or_curator!, only: %i[
    admin_metrics
    refresh_dataset_downloads
    refresh_datafile_downloads
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
    @title = "Admin metrics"
  end

  def dataset_downloads
    serve_configured_metric_file(:dataset_downloads_json)
  end

  def file_downloads
    serve_configured_metric_file(:datafile_downloads_json)
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

  def refresh_dataset_downloads
    enqueue_metric_refresh(metric_key: :dataset_downloads_json, label: "Dataset downloads JSON")
  end

  def refresh_datafile_downloads
    enqueue_metric_refresh(metric_key: :datafile_downloads_json, label: "Datafile downloads JSON")
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
      dataset_downloads_json: refresh_dataset_downloads_metrics_path,
      datafile_downloads_json: refresh_datafile_downloads_metrics_path,
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
end
