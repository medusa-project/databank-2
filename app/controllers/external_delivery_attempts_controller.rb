require "csv"

class ExternalDeliveryAttemptsController < ApplicationController
  PER_PAGE_DEFAULT = 50
  PER_PAGE_MAX = 200
  CSV_EXPORT_MAX = 5000
  SORTABLE_COLUMNS = %w[created_at integration event_name status response_status response_received_at attempt].freeze

  helper_method :sort_column, :sort_direction, :next_direction_for, :query_params_for

  def index
    authorize! :manage, Dataset

    @dataset_key = params[:dataset_key].to_s.strip
    @integration = normalize_integration(params[:integration])
    @status = normalize_status(params[:status])
    @response_status = normalize_response_status(params[:response_status])
    @event_name = params[:event_name].to_s.strip

    @integrations = ExternalDeliveryAttempt.integrations.keys
    @statuses = ExternalDeliveryAttempt.statuses.keys
    @response_statuses = ExternalDeliveryAttempt.response_statuses.keys

    base_attempts = filtered_attempts_scope

    respond_to do |format|
      format.html do
        @total_count = base_attempts.count
        @per_page = per_page
        @page = page
        @total_pages = [ (@total_count.to_f / @per_page).ceil, 1 ].max
        @attempts = base_attempts.limit(@per_page).offset((@page - 1) * @per_page)
        @orphaned_ingest_responses = IngestResponseEvent.unresolved_orphaned.order(received_at: :desc).limit(20)
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

  def replay
    authorize! :manage, Dataset

    attempt = ExternalDeliveryAttempt.includes(:dataset).find(params[:id])

    unless attempt.status == "failed"
      redirect_back fallback_location: admin_external_delivery_attempts_path, alert: "Only failed attempts can be replayed."
      return
    end

    unless replay_allowed?(attempt, force_replay: force_replay?)
      redirect_back fallback_location: admin_external_delivery_attempts_path, alert: replay_block_message(attempt)
      return
    end

    enqueued = enqueue_replay(attempt)

    if enqueued
      redirect_back fallback_location: admin_external_delivery_attempts_path, notice: "Replay enqueued for #{attempt.integration} (#{attempt.dataset.key})."
    else
      redirect_back fallback_location: admin_external_delivery_attempts_path, alert: "Replay is not supported for integration #{attempt.integration}."
    end
  end

  def replay_selected
    authorize! :manage, Dataset

    ids = selected_attempt_ids
    if ids.empty?
      redirect_back fallback_location: admin_external_delivery_attempts_path, alert: "No attempts were selected for replay."
      return
    end

    attempts = ExternalDeliveryAttempt.includes(:dataset).where(id: ids)

    replayed = 0
    skipped = 0
    blocked = 0

    attempts.each do |attempt|
      if attempt.status != "failed"
        skipped += 1
        next
      end

      unless replay_allowed?(attempt, force_replay: force_replay?)
        blocked += 1
        next
      end

      if enqueue_replay(attempt)
        replayed += 1
      else
        skipped += 1
      end
    end

    if replayed.positive?
      message = "Replayed #{replayed} selected failed attempt(s)."
      message += " Skipped #{skipped}." if skipped.positive?
      message += " Blocked #{blocked} by ingest response guardrails." if blocked.positive?
      redirect_back fallback_location: admin_external_delivery_attempts_path, notice: message
    else
      if blocked.positive? && skipped.zero?
        redirect_back fallback_location: admin_external_delivery_attempts_path, alert: "No selected attempts were replayed because ingest response guardrails blocked #{blocked}."
      else
        redirect_back fallback_location: admin_external_delivery_attempts_path, alert: "No selected attempts were replayed."
      end
    end
  end

  def acknowledge_orphan_response
    authorize! :manage, Dataset

    event = IngestResponseEvent.unresolved_orphaned.find(params[:id])
    event.acknowledge!(by_email: current_user&.email, note: params[:acknowledged_note])

    redirect_back fallback_location: admin_external_delivery_attempts_path, notice: "Orphaned ingest response acknowledged."
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: admin_external_delivery_attempts_path, alert: "Orphaned ingest response could not be found."
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

  def normalize_response_status(value)
    key = value.to_s.strip
    return nil if key.blank?
    return key if ExternalDeliveryAttempt.response_statuses.key?(key)

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
      response_status: @response_status,
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
    attempts = attempts.where(response_status: @response_status) if @response_status.present?
    attempts = attempts.where(event_name: @event_name) if @event_name.present?
    attempts
  end

  def generate_csv(attempts)
    CSV.generate(headers: true) do |csv|
      csv << [ "created_at", "dataset_key", "integration", "event_name", "status", "response_status", "response_received_at", "response_uuid", "response_target_key", "attempt", "idempotency_key", "correlation_key", "error_class", "error_message" ]

      attempts.each do |attempt|
        csv << [
          attempt.created_at.utc.iso8601,
          attempt.dataset.key,
          attempt.integration,
          attempt.event_name,
          attempt.status,
          attempt.response_status,
          attempt.response_received_at&.utc&.iso8601,
          attempt.response_uuid,
          attempt.response_target_key,
          attempt.attempt,
          attempt.idempotency_key,
          attempt.correlation_key,
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

  def enqueue_replay(attempt)
    case attempt.integration
    when "ingest"
      Ingest::PublishDatasetEventJob.perform_later(attempt.dataset_id, attempt.idempotency_key)
      true
    when "globus"
      Globus::SubmitDatasetTransferJob.perform_later(attempt.dataset_id, attempt.idempotency_key)
      true
    else
      false
    end
  end

  def selected_attempt_ids
    Array(params[:attempt_ids]).map(&:to_i).select(&:positive?).uniq
  end

  def force_replay?
    ActiveModel::Type::Boolean.new.cast(params[:force_replay])
  end

  def replay_allowed?(attempt, force_replay:)
    return true unless attempt.integration == "ingest"
    return true if force_replay

    !attempt.response_succeeded?
  end

  def replay_block_message(attempt)
    if attempt.integration == "ingest" && attempt.response_succeeded?
      "Replay blocked: ingest response is already acknowledged as succeeded. Use force replay to override."
    else
      "Replay blocked by delivery guardrails."
    end
  end
end
