class DatasetsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index pre_deposit show record_text download_metrics download_link]

  before_action :set_dataset, only: %i[show record_text download_metrics download_link confirm_review request_review edit update publish replay_failed_deliveries create_version copy_version_files pre_version version_controls submit_version_request version_acknowledge approve_version_request reject_version_request get_current_token get_new_token]

  def index
    @query = params[:q].to_s
    @per_page = per_page
    @page = page
    @report_mode = params[:report] == "generate"

    @search = Search::DatasetSearch.new(
      scope: datasets_for_current_role,
      query: @query,
      filters: dataset_filter_params,
      page: @page,
      per_page: @per_page,
      role: current_role
    )

    @datasets = @search.results.includes(:notes, :token, :version_requests, :external_delivery_attempts)
    @facet_options = @search.facet_options
    @available_facets = @search.available_facets
    @total_count = @search.total_count
    @total_pages = @search.total_pages

    return unless @report_mode

    report_query = index_query_params(report: nil, download: nil)
    report_url = datasets_url(report_query)
    @report = Dataset.citation_report(
      datasets: @search.report_results.includes(:creators, :funders),
      request_url: report_url,
      current_user: current_user
    )

    if params[:download] == "now"
      send_data @report, filename: "report.txt", type: "text/plain; charset=utf-8", disposition: "attachment"
      return
    end

    @report_back_query_params = report_query
    @report_download_query_params = index_query_params(report: "generate", download: "now")
  end

  def pre_deposit
    @title = "Pre-Deposit Considerations"
  end

  def show
    authorize! :read, @dataset
    @version_group = DatasetVersionGroup.new(@dataset)
    @version_request_history = @dataset.version_requests.order(requested_at: :desc) if logged_in? && can?(:update, @dataset)
    @latest_delivery_attempts = latest_delivery_attempts
    @failed_delivery_counts = failed_delivery_counts
    @ingest_health_summary = Ingest::HealthSummary.new(dataset: @dataset, latest_attempt: @latest_delivery_attempts["ingest"]).call
  end

  def record_text
    authorize! :read, @dataset
  end

  def download_metrics
    authorize! :read, @dataset
    respond_to do |format|
      format.json
    end
  end

  def confirm_review
    authorize! :update, @dataset
  end

  def request_review
    authorize! :update, @dataset
    @dataset.update_column(:identifier, @dataset.generate_doi) if @dataset.identifier.blank?
    render :confirm_review
  end
   def download_link
     authorize! :view_files, @dataset
     return_hash = {}

     if params.key?("web_ids")
       web_ids_str = params["web_ids"]
       web_ids = web_ids_str.split("~")

       if !web_ids.respond_to?(:count) || web_ids.count < 1
         return_hash["status"] = "error"
         return_hash["error"] = "no web_ids after split"
         render json: return_hash, content_type: request.format
         return
       end

       web_ids.each(&:strip!)
       parametrized_doi = @dataset.identifier.parameterize
       download_hash = DownloaderClient.datafiles_download_hash(
         dataset: @dataset,
         web_ids: web_ids,
         zip_name: "DOI-#{parametrized_doi}"
       )
       download_hash = download_hash.stringify_keys

       if download_hash
         if download_hash["status"] == "ok"
           web_ids.each do |web_id|
             datafile = Datafile.find_by(web_id: web_id)
             if datafile
               datafile.record_download(request.remote_ip)
             end
           end
           return_hash["status"] = "ok"
           return_hash["url"] = download_hash["download_url"]
           return_hash["total_size"] = download_hash["total_size"]
         else
           return_hash["status"] = "error"
           return_hash["error"] = download_hash["error"]
         end
       else
         return_hash["status"] = "error"
         return_hash["error"] = "nil zip link returned"
       end
       render json: return_hash, content_type: request.format
     else
       return_hash["status"] = "error"
       return_hash["error"] = "no web_ids in request"
       render json: return_hash, content_type: request.format
     end
   end
  def pre_version
    authorize! :update, @dataset

    unless @dataset.published?
      redirect_to dataset_path(@dataset), alert: "Only published datasets can be versioned."
      return
    end

    unless @dataset.version_eligible?
      redirect_to dataset_path(@dataset), alert: "A newer version has already been started for this dataset."
      return
    end

    @title = "New Version"
  end

  def version_controls
    authorize! :review_versions, @dataset
    @version_group = DatasetVersionGroup.new(@dataset)
    @previous_version = @dataset.previous_version_dataset
    @version_comparison = build_version_comparison(current: @dataset, previous: @previous_version) if @previous_version.present?
    @pending_version_requests = @dataset.version_requests.pending.order(requested_at: :desc, created_at: :desc)
    @approved_version_requests = @dataset.version_requests.approved.order(reviewed_at: :desc, updated_at: :desc)
    @rejected_version_requests = @dataset.version_requests.rejected.order(reviewed_at: :desc, updated_at: :desc)
    @title = "Version Controls"
  end

  def submit_version_request
    authorize! :update, @dataset

    unless @dataset.published?
      redirect_to dataset_path(@dataset), alert: "Only published datasets can be versioned."
      return
    end

    unless @dataset.version_eligible?
      redirect_to dataset_path(@dataset), alert: "A newer version has already been started for this dataset."
      return
    end

    existing_request = @dataset.version_requests.pending.order(requested_at: :desc).first
    if existing_request.present?
      redirect_to version_acknowledge_dataset_path(@dataset, version_request_id: existing_request.id), notice: "A pending version request already exists for this dataset."
      return
    end

    request = @dataset.version_requests.create!(
      requester_uid: current_user.uid,
      requester_email: current_user.email,
      requester_name: current_user.name,
      comment: params[:comment].to_s,
      requested_at: Time.current,
      status: :pending
    )

    VersionRequestNotificationService.request_submitted(version_request: request, dataset: @dataset)

    redirect_to version_acknowledge_dataset_path(@dataset, version_request_id: request.id)
  rescue StandardError => e
    raise e if e.is_a?(CanCan::AccessDenied)

    Rails.logger.error("submit_version_request failed for dataset #{@dataset.key}: #{e.class}: #{e.message}")
    redirect_to dataset_path(@dataset), alert: "Could not submit a version request right now. Please try again."
  end

  def version_acknowledge
    authorize! :update, @dataset
    request_id = params[:version_request_id]
    @version_request = @dataset.version_requests.pending.find_by(id: request_id)

    return if @version_request.present?

    redirect_to dataset_path(@dataset), alert: "No pending version request found."
  end

  def get_current_token
    authorize! :update, @dataset
    token = @dataset.current_token || @dataset.new_token
    render json: { token: token.identifier }
  end

  def get_new_token
    authorize! :update, @dataset
    render json: { token: @dataset.new_token.identifier }
  end

  def approve_version_request
    authorize! :review_versions, @dataset

    source_path = review_action_redirect_path(default_path: dataset_path(@dataset))
    version_request = @dataset.version_requests.pending.find(params[:version_request_id])

    new_dataset = DatasetVersionBuilder.new(
      previous_dataset: @dataset,
      new_version_uri_builder: ->(dataset) { dataset_url(dataset) }
    ).call

    version_request.update!(
      status: :approved,
      reviewed_at: Time.current,
      reviewed_by_uid: current_user.uid,
      review_note: params[:review_note].to_s,
      approved_dataset: new_dataset
    )

    VersionRequestNotificationService.request_approved(
      version_request: version_request,
      dataset: @dataset,
      approved_dataset: new_dataset
    )

    if params[:from] == "version_controls"
      redirect_to version_controls_dataset_path(@dataset), notice: "Version request approved. Draft #{new_dataset.key} is ready for editing."
    else
      redirect_to edit_dataset_path(new_dataset), notice: "Version request approved. Draft #{new_dataset.key} is ready for editing."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to source_path, alert: "No pending version request found."
  rescue ArgumentError => e
    redirect_to source_path, alert: e.message
  rescue StandardError => e
    raise e if e.is_a?(CanCan::AccessDenied)

    Rails.logger.error("approve_version_request failed for dataset #{@dataset.key}: #{e.class}: #{e.message}")
    redirect_to source_path, alert: "Could not approve the version request right now. Please try again."
  end

  def reject_version_request
    authorize! :review_versions, @dataset

    source_path = review_action_redirect_path(default_path: dataset_path(@dataset))
    version_request = @dataset.version_requests.pending.find(params[:version_request_id])

    version_request.update!(
      status: :rejected,
      reviewed_at: Time.current,
      reviewed_by_uid: current_user.uid,
      review_note: params[:review_note].to_s
    )

    redirect_to source_path, notice: "Version request rejected."
  rescue ActiveRecord::RecordNotFound
    redirect_to source_path, alert: "No pending version request found."
  rescue StandardError => e
    raise e if e.is_a?(CanCan::AccessDenied)

    Rails.logger.error("reject_version_request failed for dataset #{@dataset.key}: #{e.class}: #{e.message}")
    redirect_to source_path, alert: "Could not reject the version request right now. Please try again."
  end

  def new
    @dataset = Dataset.new
    authorize! :create, @dataset
    @title = "Deposit Agreement"
  end

  def create
    @dataset = Dataset.new(dataset_params)
    assign_depositor_fields(@dataset)
    authorize! :create, @dataset

    agreement_submission = params[:agreement_submission] == "true"
    @dataset.title = "Untitled Dataset" if agreement_submission && @dataset.title.blank?

    if agreement_submission && !valid_deposit_agreement_submission?(@dataset)
      @title = "Deposit Agreement"
      render :new, status: :unprocessable_entity
      return
    end

    if @dataset.save
      if agreement_submission
        redirect_to edit_dataset_path(@dataset), notice: "Deposit agreement accepted. Continue with dataset metadata."
      else
        redirect_to dataset_path(@dataset), notice: "Dataset created."
      end
    else
      @title = "Deposit Agreement"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize! :update, @dataset
  end

  def update
    authorize! :update, @dataset
    requested_org_mode = if dataset_params.key?(:org_creators)
      ActiveModel::Type::Boolean.new.cast(dataset_params[:org_creators])
    else
      @dataset.org_creators
    end

    begin
      Dataset.transaction do
        @dataset.update!(dataset_params)
        @dataset.prune_creators_for_mode!(org_mode: requested_org_mode)
      end
      if params[:save_and_exit].present?
        redirect_to datasets_path, notice: "Dataset updated and saved."
      else
        redirect_to dataset_path(@dataset), notice: "Dataset updated."
      end
    rescue ActiveRecord::RecordInvalid
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

  def create_version
    authorize! :update, @dataset

    unless @dataset.published?
      redirect_to dataset_path(@dataset), alert: "Only published datasets can be versioned."
      return
    end

    unless @dataset.version_eligible?
      redirect_to dataset_path(@dataset), alert: "A newer version has already been started for this dataset."
      return
    end

    new_dataset = DatasetVersionBuilder.new(
      previous_dataset: @dataset,
      new_version_uri_builder: ->(dataset) { dataset_url(dataset) }
    ).call

    redirect_to edit_dataset_path(new_dataset), notice: "Draft version created from #{@dataset.key}."
  rescue ArgumentError => e
    redirect_to dataset_path(@dataset), alert: e.message
  rescue StandardError => e
    raise e if e.is_a?(CanCan::AccessDenied)

    Rails.logger.error("create_version failed for dataset #{@dataset.key}: #{e.class}: #{e.message}")
    redirect_to dataset_path(@dataset), alert: "Could not create a new version right now. Please try again."
  end

  def copy_version_files
    authorize! :update, @dataset
    redirect_path = copy_version_files_redirect_path

    unless @dataset.draft?
      redirect_to redirect_path, alert: "Version files can only be copied into a draft dataset."
      return
    end

    unless @dataset.previous_version_dataset.present?
      redirect_to redirect_path, alert: "No previous version dataset found to copy files from."
      return
    end

    result = DatasetVersionFileCopyService.new(version_dataset: @dataset).call
    message = "Copied #{result.copied_count} file(s) from the previous version"
    message += ", skipped #{result.skipped_count} duplicate(s)" if result.skipped_count.positive?

    redirect_to redirect_path, notice: "#{message}."
  rescue ArgumentError => e
    redirect_to redirect_path, alert: e.message
  rescue StandardError => e
    raise e if e.is_a?(CanCan::AccessDenied)

    Rails.logger.error("copy_version_files failed for dataset #{@dataset.key}: #{e.class}: #{e.message}")
    redirect_to redirect_path, alert: "Could not copy files from the previous version. Please try again."
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
    blocked = 0
    replay_targets.each do |attempt|
      if attempt.integration == "ingest" && attempt.response_succeeded? && !force_replay_requested?
        blocked += 1
        next
      end

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
      message = "Requeued #{replayed} failed external delivery attempt(s) for #{target_label}."
      message += " Blocked #{blocked} acknowledged ingest attempt(s)." if blocked.positive?
      redirect_to dataset_path(@dataset), notice: message
    else
      if blocked.positive?
        redirect_to dataset_path(@dataset), alert: "No failed external deliveries were replayed for #{target_label}; #{blocked} acknowledged ingest attempt(s) were blocked."
      else
        redirect_to dataset_path(@dataset), alert: "No failed external deliveries to replay for #{target_label}."
      end
    end
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:id])

    unless @dataset.publicly_readable_now? || logged_in?
      redirect_to login_path, alert: "Please sign in to continue."
    end
  end

  def build_version_comparison(current:, previous:)
    {
      metadata_rows: [
        comparison_row(label: "Title", current: current.title, previous: previous.title),
        comparison_row(label: "Description", current: current.description, previous: previous.description),
        comparison_row(label: "Keywords", current: current.keywords, previous: previous.keywords),
        comparison_row(label: "Subject", current: current.subject, previous: previous.subject),
        comparison_row(label: "License", current: current.license, previous: previous.license),
        comparison_row(label: "Publisher", current: current.publisher, previous: previous.publisher),
        comparison_row(label: "Depositor Name", current: current.depositor_name, previous: previous.depositor_name),
        comparison_row(label: "Depositor Email", current: current.depositor_email, previous: previous.depositor_email)
      ],
      creators_added: creator_signatures(current.creators) - creator_signatures(previous.creators),
      creators_removed: creator_signatures(previous.creators) - creator_signatures(current.creators),
      funders_added: funder_signatures(current.funders) - funder_signatures(previous.funders),
      funders_removed: funder_signatures(previous.funders) - funder_signatures(current.funders),
      related_materials_added: related_material_signatures(current.nonversion_related_materials) - related_material_signatures(previous.nonversion_related_materials),
      related_materials_removed: related_material_signatures(previous.nonversion_related_materials) - related_material_signatures(current.nonversion_related_materials),
      files_added: file_signatures(current.datafiles) - file_signatures(previous.datafiles),
      files_removed: file_signatures(previous.datafiles) - file_signatures(current.datafiles)
    }
  end

  def comparison_row(label:, current:, previous:)
    {
      label: label,
      current: current.to_s,
      previous: previous.to_s,
      different: current.to_s != previous.to_s
    }
  end

  def creator_signatures(creators)
    creators.map { |creator| [ creator.name.to_s, creator.email.to_s ] }.sort.map { |name, email| email.present? ? "#{name} <#{email}>" : name }
  end

  def force_replay_requested?
    ActiveModel::Type::Boolean.new.cast(params[:force_replay])
  end

  def funder_signatures(funders)
    funders.map { |funder| [ funder.name.to_s, funder.identifier.to_s, funder.award_number.to_s ] }.sort.map do |name, identifier, award_number|
      [ name, identifier, award_number ].reject(&:blank?).join(" | ")
    end
  end

  def related_material_signatures(materials)
    materials.map { |material| [ material.title.to_s, material.uri.to_s, material.relation_type.to_s ] }.sort.map do |title, uri, relation_type|
      [ title, uri, relation_type ].reject(&:blank?).join(" | ")
    end
  end

  def file_signatures(files)
    files.map { |file| [ file.binary_name.to_s, file.binary_size.to_i ] }.sort.map do |binary_name, binary_size|
      binary_size.positive? ? "#{binary_name} (#{binary_size} bytes)" : binary_name
    end
  end

  def copy_version_files_redirect_path
    return edit_dataset_path(@dataset) unless params[:from] == "version_controls" && can?(:review_versions, @dataset)

    version_controls_dataset_path(@dataset)
  end

  def review_action_redirect_path(default_path:)
    return default_path unless params[:from] == "version_controls" && can?(:review_versions, @dataset)

    version_controls_dataset_path(@dataset)
  end

  def dataset_params
    params.require(:dataset).permit(
      :title,
      :description,
      :keywords,
      :subject,
      :license,
      :publisher,
      :identifier,
      :embargo,
      :release_date,
      :complete,
      :search,
      :dataset_version,
      :is_test,
      :is_import,
      :medusa_dataset_dir,
      :external_files_link,
      :external_files_note,
      :version_comment,
      :have_permission,
      :removed_private,
      :agree,
      :org_creators,
      :corresponding_creator_name,
      :corresponding_creator_email,
      datafiles_attributes: [
        :id,
        :binary_name,
        :binary_size,
        :description,
        :row_position,
        :position,
        :_destroy,
        :binary
      ],
      creators_attributes: [
        :id,
        :name,
        :family_name,
        :given_name,
        :institution_name,
        :identifier,
        :identifier_scheme,
        :type_of,
        :row_position,
        :row_order,
        :position,
        :email,
        :contact,
        :is_contact,
        :_destroy
      ],
      contributors_attributes: [
        :id,
        :name,
        :family_name,
        :given_name,
        :institution_name,
        :identifier,
        :identifier_scheme,
        :type_of,
        :row_position,
        :row_order,
        :position,
        :email,
        :role,
        :is_contact,
        :_destroy
      ],
      funders_attributes: [
        :id,
        :code,
        :name,
        :identifier,
        :identifier_scheme,
        :grant,
        :award_number,
        :row_position,
        :position,
        :_destroy
      ],
      related_materials_attributes: [
        :id,
        :title,
        :material_type,
        :selected_type,
        :availability,
        :link,
        :uri,
        :uri_type,
        :citation,
        :datacite_list,
        :note,
        :feature,
        :relation_type,
        :row_position,
        :position,
        :_destroy
      ]
    )
  end

  def assign_depositor_fields(dataset)
    dataset.owner_uid      = current_user.uid
    dataset.depositor_name  = current_user.name
    dataset.depositor_email = current_user.email
  end

  def valid_deposit_agreement_submission?(dataset)
    valid = true

    if dataset.have_permission != "yes"
      dataset.errors.add(:have_permission, "must be Yes to continue.")
      valid = false
    end

    unless %w[yes na].include?(dataset.removed_private)
      dataset.errors.add(:removed_private, "must be Yes or Not applicable to continue.")
      valid = false
    end

    if dataset.agree != "yes"
      dataset.errors.add(:agree, "must be Yes to continue.")
      valid = false
    end

    valid
  end

  def public_datasets
    return Dataset.all if logged_in? && current_user.curator?

    if logged_in?
      owned   = Dataset.where(depositor_email: current_user.email)
      granted = Dataset.where(id: DatasetAccessGrant.for_email(current_user.email).select(:dataset_id))
      public  = Dataset.publicly_readable_now
      Dataset.where(id: owned).or(Dataset.where(id: public)).or(Dataset.where(id: granted)).distinct
    else
      Dataset.publicly_readable_now
    end
  end

  def current_role
    return "guest" unless logged_in?

    current_user.curator? ? "admin" : "depositor"
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

  def pagination_items
    return [] if @total_pages <= 1

    pages = []
    pages.concat((1..[ 3, @total_pages ].min).to_a)
    pages.concat(([ @page - 1, 1 ].max..[ @page + 1, @total_pages ].min).to_a)
    pages.concat(([ @total_pages - 1, 1 ].max..@total_pages).to_a)

    ordered_pages = pages.uniq.sort

    ordered_pages.each_with_object([]) do |page_number, items|
      if items.last.is_a?(Integer) && page_number - items.last > 1
        items << :gap
      end
      items << page_number
    end
  end

  helper_method :index_query_params, :pagination_items

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
