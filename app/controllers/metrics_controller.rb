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

  before_action :require_admin!, only: %i[
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
    @modified_times = Metric.modified_times
    @refresh_status = Metric.refresh_status
    @metrics_rows = [
      {
        key: :dataset_downloads_json,
        title: "Dataset downloads JSON",
        href: "/dataset_downloads.json",
        refresh_path: "/metrics/refresh_dataset_downloads",
        description: "Downloads calculated per dataset per day."
      },
      {
        key: :datafile_downloads_json,
        title: "Datafile downloads JSON",
        href: "/datafile_downloads.json",
        refresh_path: "/metrics/refresh_datafile_downloads",
        description: "Downloads calculated per datafile per day."
      },
      {
        key: :datasets_tsv,
        title: "Datasets TSV",
        href: "/datasets.tsv",
        refresh_path: "/metrics/refresh_datasets_tsv",
        description: "Tab-separated dataset-level metrics report."
      },
      {
        key: :datafiles_csv,
        title: "Datafiles CSV",
        href: "/datafiles.csv",
        refresh_path: "/metrics/refresh_datafiles_csv",
        description: "CSV of datafile metadata and download totals."
      },
      {
        key: :container_contents_csv,
        title: "Container Contents CSV",
        href: "/archive_file_contents.csv",
        refresh_path: "/metrics/refresh_container_contents_csv",
        description: "CSV of archive container file contents."
      },
      {
        key: :related_materials_csv,
        title: "Related Materials CSV",
        href: "/related_materials.csv",
        refresh_path: "/metrics/refresh_related_materials_csv",
        description: "CSV of related material identifiers and relation types."
      },
      {
        key: :funders_csv,
        title: "Funders CSV",
        href: "/funders.csv",
        refresh_path: "/metrics/refresh_funders_csv",
        description: "CSV of funder and grant information."
      }
    ]
    @title = "Admin metrics"
  end

  def dataset_downloads
    serve_metrics_file(Rails.root.join("public/dataset_downloads.json"), type: "application/json")
  end

  def file_downloads
    serve_metrics_file(Rails.root.join("public/datafile_downloads.json"), type: "application/json")
  end

  def datafiles_simple_list
    public_dataset_ids = Dataset.publicly_readable_now.select(:id)
    @datafiles = Datafile.where(dataset_id: public_dataset_ids)

    respond_to do |format|
      format.json
    end
  end

  def datafiles_csv
    serve_metrics_file(METRICS_CONFIG[:datafiles_csv][:relative_path], type: "text/csv")
  end

  def funders_csv
    serve_metrics_file(METRICS_CONFIG[:funders_csv][:relative_path], type: "text/csv")
  end

  def archived_content_csv
    serve_metrics_file(Rails.root.join("public/archive_file_contents.csv"), type: "text/csv")
  end

  def related_materials_csv
    serve_metrics_file(METRICS_CONFIG[:related_materials_csv][:relative_path], type: "text/csv")
  end

  def refresh_dataset_downloads
    enqueue_metric_refresh(:dataset_downloads_json, "Dataset downloads JSON")
  end

  def refresh_datafile_downloads
    enqueue_metric_refresh(:datafile_downloads_json, "Datafile downloads JSON")
  end

  def refresh_datasets_tsv
    enqueue_metric_refresh(:datasets_tsv, "Datasets TSV")
  end

  def refresh_datafiles_csv
    enqueue_metric_refresh(:datafiles_csv, "Datafiles CSV")
  end

  def refresh_container_csv
    enqueue_metric_refresh(:container_contents_csv, "Container contents CSV")
  end

  def refresh_funders_csv
    enqueue_metric_refresh(:funders_csv, "Funders CSV")
  end

  def refresh_related_materials_csv
    enqueue_metric_refresh(:related_materials_csv, "Related materials CSV")
  end

  def refresh_container_contents_csv
    enqueue_metric_refresh(:container_contents_csv, "Container contents CSV")
  end

  private

  def enqueue_metric_refresh(metric_key, label)
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

  def require_admin!
    return if current_user&.admin?

    redirect_to metrics_path, alert: "You are not authorized to perform this action."
  end
end
