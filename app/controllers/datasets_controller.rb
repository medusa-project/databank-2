class DatasetsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index show]

  before_action :set_dataset, only: %i[show edit update publish replay_failed_deliveries]

  def index
    @query = params[:q].to_s
    @subject = params[:subject].to_s

    @datasets = Search::DatasetSearch.new(
      scope: public_datasets,
      query: @query,
      subject: @subject
    ).results
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
