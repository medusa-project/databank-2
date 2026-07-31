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
    curator_download_metrics
    download_metrics_breakdown
  ]

  before_action :require_admin!, only: %i[
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
    @download_metrics_summary = build_download_metrics_summary
    @title = "Curator Metrics"
  end

  def curator_download_metrics
    @download_metrics_summary = build_download_metrics_summary
    @download_metrics_yearly_summary = build_download_metrics_yearly_summary
    @title = "Download Metrics"
  end

  def download_metrics_breakdown
    summary = build_download_metrics_summary
    yearly = build_download_metrics_yearly_summary

    render json: {
      generated_at: Time.current.utc.iso8601,
      current_calendar_year: summary[:current_calendar_year],
      current_fiscal_year_label: summary[:current_fiscal_year_label],
      summary: {
        dataset: summary[:dataset],
        datafile: summary[:datafile]
      },
      calendar_years: yearly[:calendar_rows],
      fiscal_years: yearly[:fiscal_rows]
    }
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

  def require_admin!
    return if current_user&.admin?

    redirect_to metrics_path, alert: "You are not authorized to perform this action."
  end

  def build_download_metrics_summary
    public_dataset_keys = Dataset.files_publicly_readable_now_scope.pluck(:key)
    dataset_scope = DatasetDownloadTally.where(dataset_key: public_dataset_keys)
    datafile_scope = FileDownloadTally.where(dataset_key: public_dataset_keys)

    today = Date.current
    calendar_range = Date.new(today.year, 1, 1)..Date.new(today.year, 12, 31)
    fiscal_start_year = today.month >= 7 ? today.year : today.year - 1
    fiscal_range = Date.new(fiscal_start_year, 7, 1)..Date.new(fiscal_start_year + 1, 6, 30)

    {
      current_calendar_year: today.year,
      current_fiscal_year_label: format("FY%02d", fiscal_start_year % 100),
      dataset: {
        all_time: dataset_scope.sum(:tally),
        current_calendar_year: dataset_scope.where(download_date: calendar_range).sum(:tally),
        current_fiscal_year: dataset_scope.where(download_date: fiscal_range).sum(:tally)
      },
      datafile: {
        all_time: datafile_scope.sum(:tally),
        current_calendar_year: datafile_scope.where(download_date: calendar_range).sum(:tally),
        current_fiscal_year: datafile_scope.where(download_date: fiscal_range).sum(:tally)
      }
    }
  end

  def build_download_metrics_yearly_summary
    public_dataset_keys = Dataset.files_publicly_readable_now_scope.pluck(:key)
    dataset_scope = DatasetDownloadTally.where(dataset_key: public_dataset_keys)
    datafile_scope = FileDownloadTally.where(dataset_key: public_dataset_keys)

    min_date = [ dataset_scope.minimum(:download_date), datafile_scope.minimum(:download_date) ].compact.min
    today = Date.current

    current_calendar_year = today.year
    current_fiscal_start_year = today.month >= 7 ? today.year : today.year - 1

    earliest_calendar_year = min_date ? min_date.year : current_calendar_year
    earliest_fiscal_start_year = if min_date
      min_date.month >= 7 ? min_date.year : min_date.year - 1
    else
      current_fiscal_start_year
    end

    calendar_years = (earliest_calendar_year..current_calendar_year).to_a.reverse.first(10)
    fiscal_start_years = (earliest_fiscal_start_year..current_fiscal_start_year).to_a.reverse.first(10)

    {
      current_calendar_year: current_calendar_year,
      current_fiscal_year_label: format_fiscal_label(current_fiscal_start_year),
      calendar_rows: calendar_years.map do |year|
        range = Date.new(year, 1, 1)..Date.new(year, 12, 31)
        {
          year_label: year.to_s,
          dataset_downloads: dataset_scope.where(download_date: range).sum(:tally),
          datafile_downloads: datafile_scope.where(download_date: range).sum(:tally)
        }
      end,
      fiscal_rows: fiscal_start_years.map do |start_year|
        range = Date.new(start_year, 7, 1)..Date.new(start_year + 1, 6, 30)
        {
          fiscal_year_label: format_fiscal_label(start_year),
          date_range_label: "#{range.begin.iso8601} to #{range.end.iso8601}",
          dataset_downloads: dataset_scope.where(download_date: range).sum(:tally),
          datafile_downloads: datafile_scope.where(download_date: range).sum(:tally)
        }
      end
    }
  end

  def format_fiscal_label(start_year)
    format("FY%02d", start_year % 100)
  end
end
