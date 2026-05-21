require "csv"

class ExternalDeliveryAttemptsController < ApplicationController
  PER_PAGE_DEFAULT = 50
  PER_PAGE_MAX = 200
  CSV_EXPORT_MAX = 5000
  SORTABLE_COLUMNS = %w[created_at integration event_name status attempt].freeze

  helper_method :sort_column, :sort_direction, :next_direction_for, :query_params_for

  def index
    authorize! :manage, Dataset

    @dataset_key = params[:dataset_key].to_s.strip
    @integration = normalize_integration(params[:integration])
    @status = normalize_status(params[:status])
    @event_name = params[:event_name].to_s.strip

    @integrations = ExternalDeliveryAttempt.integrations.keys
    @statuses = ExternalDeliveryAttempt.statuses.keys

    base_attempts = filtered_attempts_scope

    respond_to do |format|
      format.html do
        @total_count = base_attempts.count
        @per_page = per_page
        @page = page
        @total_pages = [ (@total_count.to_f / @per_page).ceil, 1 ].max
        @attempts = base_attempts.limit(@per_page).offset((@page - 1) * @per_page)
      end

      format.csv do
        attempts = base_attempts.limit(CSV_EXPORT_MAX)
        send_data(
          generate_csv(attempts),
          filename: csv_filename,
          type: "text/csv"
        )
      end
    end
  end

  private

  def normalize_integration(value)
    key = value.to_s.strip
    return nil if key.blank?
    return key if ExternalDeliveryAttempt.integrations.key?(key)

    nil
  end

  def normalize_status(value)
    key = value.to_s.strip
    return nil if key.blank?
    return key if ExternalDeliveryAttempt.statuses.key?(key)

    nil
  end

  def sort_column
    requested = params[:sort].to_s
    return requested if SORTABLE_COLUMNS.include?(requested)

    "created_at"
  end

  def sort_direction
    params[:direction].to_s == "asc" ? :asc : :desc
  end

  def next_direction_for(column)
    if sort_column == column && sort_direction == :asc
      "desc"
    else
      "asc"
    end
  end

  def per_page
    requested = params[:per_page].to_i
    return PER_PAGE_DEFAULT if requested <= 0

    [ requested, PER_PAGE_MAX ].min
  end

  def page
    requested = params[:page].to_i
    requested.positive? ? requested : 1
  end

  def query_params_for(overrides = {})
    {
      dataset_key: @dataset_key,
      integration: @integration,
      status: @status,
      event_name: @event_name,
      per_page: @per_page,
      sort: sort_column,
      direction: sort_direction,
      page: @page
    }.merge(overrides)
  end

  def filtered_attempts_scope
    attempts = ExternalDeliveryAttempt
      .includes(:dataset)
      .order(sort_column => sort_direction, id: :desc)

    if @dataset_key.present?
      attempts = attempts.joins(:dataset).where(datasets: { key: @dataset_key })
    end

    attempts = attempts.where(integration: @integration) if @integration.present?
    attempts = attempts.where(status: @status) if @status.present?
    attempts = attempts.where(event_name: @event_name) if @event_name.present?
    attempts
  end

  def generate_csv(attempts)
    CSV.generate(headers: true) do |csv|
      csv << [ "created_at", "dataset_key", "integration", "event_name", "status", "attempt", "idempotency_key", "error_class", "error_message" ]

      attempts.each do |attempt|
        csv << [
          attempt.created_at.utc.iso8601,
          attempt.dataset.key,
          attempt.integration,
          attempt.event_name,
          attempt.status,
          attempt.attempt,
          attempt.idempotency_key,
          attempt.error_class,
          attempt.error_message
        ]
      end
    end
  end

  def csv_filename
    suffix = Time.current.utc.strftime("%Y%m%d%H%M%S")
    "external_delivery_attempts_#{suffix}.csv"
  end
end
