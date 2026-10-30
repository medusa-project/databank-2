class DatasetsController < ApplicationController
  include ShareCodeAccess
  include DatasetsController::Versionable
  include DatasetsController::Publishable
  include DatasetsController::Holdable

  skip_before_action :authenticate_user!, only: %i[index pre_deposit show download_endnote_xml download_ris download_bibtex download_plaintext_citation record_text download_metrics download_link open_in_granite open_in_globus]

  before_action :set_dataset, only: %i[show download_endnote_xml download_ris download_bibtex download_plaintext_citation record_text download_metrics download_link open_in_granite open_in_globus import_from_globus confirm_review request_review edit update publish replay_failed_deliveries create_version copy_version_files pre_version version_controls suppression_controls suppression_action suppress_changelog unsuppress_changelog temporarily_suppress_files temporarily_suppress_metadata unsuppress permanently_suppress_files permanently_suppress_metadata suppress_review unsuppress_review draft_to_version version_to_draft submit_version_request version_acknowledge approve_version_request reject_version_request get_current_token get_new_token share remove_sharing_link]

  def share
    authorize! :update, @dataset

    if @dataset.files_publicly_readable_now?
      return sharing_error(message: "This dataset is public and does not need a private sharing link.")
    end

    @dataset.with_lock do
      @dataset.create_share_code! unless @dataset.current_share_code
    end

    respond_to do |format|
      format.html do
        redirect_to dataset_path(@dataset), notice: "Private sharing link generated. Anybody with this link can access the metadata and files. The link expires 12 months after generation or when the dataset is released."
      end
      format.json { render json: { private_share_link: @dataset.sharing_link }, status: :ok }
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("Error generating sharing link for #{@dataset.key}: #{e.class}")
    sharing_error(message: "Error generating share link.")
  end

  def remove_sharing_link
    authorize! :update, @dataset

    unless @dataset.share_code
      Rails.logger.warn("Error removing sharing link for #{@dataset.key}: no share code")
      return sharing_error(message: "Unexpected Error")
    end

    @dataset.share_code.destroy!
    respond_to do |format|
      format.html { redirect_to dataset_path(@dataset), notice: "Private Sharing Link has been removed." }
      format.json { render json: { private_share_link: nil }, status: :ok }
    end
  end

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
      role: current_role,
      current_user: current_user
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

    # File download availability
    @dataset_preserved = @dataset.fileset_preserved?
    @globus_downloadable = @dataset.globus_downloadable?
    @dataset_aggregate_downloadable = (@dataset_preserved || @globus_downloadable) && !@dataset.external_files?
  end

  def record_text
    authorize! :read, @dataset
  end

  def download_endnote_xml
    send_citation_export(@dataset.citation_endnote_xml, type: "application/xml", extension: "xml")
  end

  def download_ris
    send_citation_export(@dataset.citation_ris, type: "application/x-research-info-systems", extension: "ris")
  end

  def download_bibtex
    send_citation_export(@dataset.citation_bibtex, type: "application/x-bibtex", extension: "bib")
  end

  def download_plaintext_citation
    send_citation_export("#{@dataset.plain_text_citation}\n", type: "text/plain", extension: "txt")
  end

  def download_metrics
    authorize! :read, @dataset
    respond_to do |format|
      format.json
    end
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

  def open_in_globus
    authorize! :view_files, @dataset
    unless @dataset.globus_downloadable?
      redirect_to dataset_path(@dataset), alert: "Files are not currently available for public download through Globus."
      return
    end

    url = @dataset.globus_download_dir
    @dataset.datafiles.find_each { |datafile| datafile.record_download(request.remote_ip) }
    redirect_to url, allow_other_host: true
  rescue Dataset::Globusable::Error => e
    Rails.logger.error("Globus download failed for #{@dataset.key}: #{e.message}")
    redirect_to dataset_path(@dataset), alert: "Globus download is not configured correctly. Please contact the Research Data Service."
  end

  def import_from_globus
    authorize! :manage, @dataset

    result = @dataset.import_from_globus
    status = result[:failed].positive? || result[:skipped_invalid].positive? ? :unprocessable_content : :ok
    globus_import_response(result, status: status)
  rescue Dataset::Globusable::Error, MedusaStorage::InvalidKeyError, Aws::S3::Errors::ServiceError => e
    Rails.logger.error("Globus import failed for #{@dataset.key}: #{e.class}: #{e.message}")
    globus_import_response({ error: "Could not import files from Globus. Please verify the ingest directory and try again." }, status: :unprocessable_content)
  end

  def open_in_granite
    authorize! :view_files, @dataset

    if @dataset.external_files_link.blank?
      redirect_to dataset_path(@dataset), alert: "No external files link is available for this dataset."
      return
    end

    redirect_url = safe_external_files_url(@dataset.external_files_link)
    if redirect_url.nil?
      redirect_to dataset_path(@dataset), alert: "The external files link is not a valid URL."
      return
    end

    @dataset.datafiles.find_each do |datafile|
      datafile.record_download(request.remote_ip)
    end

    redirect_to redirect_url, allow_other_host: true
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
    @version_group = DatasetVersionGroup.new(@dataset)
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
        args = [ @dataset.id, attempt.idempotency_key ]
        args << attempt.details["datafile_id"] if attempt.details["datafile_id"].present?
        Ingest::PublishDatasetEventJob.perform_later(*args)
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

  def globus_import_response(result, status:)
    respond_to do |format|
      format.json { render json: result, status: status }
      format.html do
        if status == :ok
          redirect_to edit_dataset_path(@dataset), notice: "Imported #{result[:created]} file(s) from Globus; skipped #{result[:skipped_existing]} existing file(s)."
        else
          redirect_to edit_dataset_path(@dataset), alert: result[:error] || "Some Globus files could not be imported. Imported #{result[:created]} file(s); failed #{result[:failed]}; invalid #{result[:skipped_invalid]}. Check the logs before retrying."
        end
      end
    end
  end

  def send_citation_export(content, type:, extension:)
    authorize! :read, @dataset
    send_data content, type: "#{type}; charset=utf-8", disposition: "attachment",
                       filename: @dataset.citation_export_filename(extension)
  end

  def sharing_error(message:)
    respond_to do |format|
      format.html { redirect_to dataset_path(@dataset), alert: message }
      format.json { render json: { private_share_link: nil, error: message }, status: :unprocessable_content }
    end
  end

  def set_dataset
    @dataset = dataset_lookup_scope.find_by!(key: params[:id])
    grant_share_code_access(dataset: @dataset) if %w[show record_text download_metrics download_link open_in_granite].include?(action_name)

    unless @dataset.publicly_readable_now? || logged_in? || @shared_by_link
      redirect_to login_path, alert: "Please sign in to continue."
    end
  end

  def dataset_lookup_scope
    return Dataset.all unless action_name == "show"

    Dataset.includes(
      :contributors,
      :creators,
      :funders,
      :related_materials,
      :version_requests,
      datafiles: [ :nested_items, { binary_attachment: :blob } ]
    )
  end

  def force_replay_requested?
    ActiveModel::Type::Boolean.new.cast(params[:force_replay])
  end

  def safe_external_files_url(url)
    parsed = URI.parse(url.to_s)
    return nil unless parsed.is_a?(URI::HTTP)
    return nil if parsed.host.blank?

    parsed.to_s
  rescue URI::InvalidURIError
    nil
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
      :suppress_changelog,
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
    return Dataset.all if acting_as_curator_role?

    if logged_in?
      owned   = Dataset.where(depositor_email: current_user.email)
      granted = Dataset.where(id: DatasetAccessGrant.for_email(current_user.email).select(:dataset_id))
      public  = Dataset.publicly_readable_now
      Dataset.where(id: owned).or(Dataset.where(id: public)).or(Dataset.where(id: granted))
        .where("COALESCE(BTRIM(hold_state), '') <> ?", Dataset::HOLD_PERM_METADATA).distinct
    else
      Dataset.publicly_readable_now
    end
  end

  def current_role
    return "guest" unless logged_in?

    return "admin" if acting_as_curator_role?
    return "depositor" if current_user.role == "depositor"

    "guest"
  end

  def datasets_for_current_role
    public_datasets
  end

  def acting_as_curator_role?
    logged_in? && [ "admin", "curator" ].include?(current_user.role.to_s)
  end

  def dataset_filter_params
    {
      editor: params[:editor],
      subjects: params[:subjects],
      licenses: params[:licenses],
      funders: params[:funders],
      publication_years: params[:publication_years],
      visibility_states: params[:visibility_states],
      depositors: params[:depositors],
      external_files: params[:external_files]
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
      editor: params[:editor],
      subjects: params[:subjects],
      licenses: params[:licenses],
      funders: params[:funders],
      publication_years: params[:publication_years],
      visibility_states: params[:visibility_states],
      depositors: params[:depositors],
      external_files: params[:external_files],
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
