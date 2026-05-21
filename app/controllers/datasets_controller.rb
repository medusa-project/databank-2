class DatasetsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index show]

  before_action :set_dataset, only: %i[show edit update publish replay_failed_deliveries]

  def index
    @query = params[:q].to_s
    @per_page = per_page
    @page = page

    @search = Search::DatasetSearch.new(
      scope: datasets_for_current_role,
      query: @query,
      filters: dataset_filter_params,
      page: @page,
      per_page: @per_page,
      role: current_role
    )

    @datasets = @search.results
    @facet_options = @search.facet_options
    @available_facets = @search.available_facets
    @total_count = @search.total_count
    @total_pages = @search.total_pages
  end

  def show
    authorize! :read, @dataset
    @latest_delivery_attempts = latest_delivery_attempts
    @failed_delivery_counts = failed_delivery_counts
  end

  def new
    @dataset = Dataset.new
    authorize! :create, @dataset
  end

  def create
    @dataset = Dataset.new(dataset_params)
    assign_depositor_fields(@dataset)
    authorize! :create, @dataset

    if @dataset.save
      redirect_to dataset_path(@dataset), notice: "Dataset created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize! :update, @dataset
  end

  def update
    authorize! :update, @dataset

    if @dataset.update(dataset_params)
      redirect_to dataset_path(@dataset), notice: "Dataset updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def publish
    authorize! :update, @dataset

    if @dataset.ready_to_publish?
      identifier = Doi::IdentifierService.new(@dataset).mint_for_publish!

      @dataset.update!(
        publication_state: :published,
        published_at: Time.current,
        identifier: identifier
      )
      Ingest::PublishDatasetEventJob.perform_later(@dataset.id)
      Globus::SubmitDatasetTransferJob.perform_later(@dataset.id)
      redirect_to dataset_path(@dataset), notice: "Dataset published. DOI: #{@dataset.identifier}"
    else
      redirect_to dataset_path(@dataset), alert: "Cannot publish: #{@dataset.missing_publish_fields.join(', ')} required."
    end
  end

  def replay_failed_deliveries
    authorize! :manage, Dataset

    selected_integration = replay_integration

    failures = ExternalDeliveryAttempt
      .where(dataset: @dataset, event_name: "dataset.published", status: :failed)
      .order(created_at: :desc)
    failures = failures.where(integration: selected_integration) if selected_integration.present?

    replay_targets = failures.uniq { |attempt| [ attempt.integration, attempt.idempotency_key ] }

    replayed = 0
    replay_targets.each do |attempt|
      case attempt.integration
      when "ingest"
        Ingest::PublishDatasetEventJob.perform_later(@dataset.id, attempt.idempotency_key)
        replayed += 1
      when "globus"
        Globus::SubmitDatasetTransferJob.perform_later(@dataset.id, attempt.idempotency_key)
        replayed += 1
      end
    end

    target_label = selected_integration || "all"

    if replayed.positive?
      redirect_to dataset_path(@dataset), notice: "Requeued #{replayed} failed external delivery attempt(s) for #{target_label}."
    else
      redirect_to dataset_path(@dataset), alert: "No failed external deliveries to replay for #{target_label}."
    end
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:id])

    unless @dataset.published? || logged_in?
      redirect_to login_path, alert: "Please sign in to continue."
    end
  end

  def dataset_params
    params.require(:dataset).permit(:title, :description, :keywords, :subject, :license, :publisher)
  end

  def assign_depositor_fields(dataset)
    dataset.owner_uid      = current_user.uid
    dataset.depositor_name  = current_user.name
    dataset.depositor_email = current_user.email
  end

  def public_datasets
    return Dataset.all if logged_in? && current_user.admin?

    if logged_in?
      owned   = Dataset.where(depositor_email: current_user.email)
      public  = Dataset.published
      Dataset.where(id: owned).or(Dataset.where(id: public))
    else
      Dataset.published
    end
  end

  def current_role
    return "guest" unless logged_in?

    current_user.admin? ? "admin" : "depositor"
  end

  def datasets_for_current_role
    public_datasets
  end

  def dataset_filter_params
    {
      subjects: params[:subjects],
      licenses: params[:licenses],
      funders: params[:funders],
      publication_years: params[:publication_years],
      publication_states: params[:publication_states],
      depositors: params[:depositors]
    }
  end

  def per_page
    requested = params[:per_page].to_i
    return Search::DatasetSearch::DEFAULT_PER_PAGE if requested <= 0

    [ requested, Search::DatasetSearch::MAX_PER_PAGE ].min
  end

  def page
    requested = params[:page].to_i
    requested.positive? ? requested : 1
  end

  def index_query_params(overrides = {})
    {
      q: @query,
      per_page: @per_page,
      subjects: params[:subjects],
      licenses: params[:licenses],
      funders: params[:funders],
      publication_years: params[:publication_years],
      publication_states: params[:publication_states],
      depositors: params[:depositors],
      page: @page
    }.merge(overrides)
  end

  helper_method :index_query_params

  def latest_delivery_attempts
    ExternalDeliveryAttempt
      .where(dataset: @dataset, event_name: "dataset.published")
      .order(created_at: :desc)
      .group_by(&:integration)
      .transform_values(&:first)
  end

  def failed_delivery_counts
    ExternalDeliveryAttempt
      .where(dataset: @dataset, event_name: "dataset.published", status: :failed)
      .group(:integration)
      .count
  end

  def replay_integration
    value = params[:integration].to_s.strip
    return nil if value.blank? || value == "all"
    return value if ExternalDeliveryAttempt.integrations.key?(value)

    nil
  end
end
