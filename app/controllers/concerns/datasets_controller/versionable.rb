module DatasetsController::Versionable
  extend ActiveSupport::Concern

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

  def draft_to_version
    authorize! :review_versions, @dataset

    unless @dataset.draft?
      redirect_to dataset_path(@dataset), alert: "Publication state must be draft to designate version-type draft."
      return
    end

    @dataset.hold_state = Dataset::HOLD_TEMP_VERSION

    if @dataset.save
      redirect_to dataset_path(@dataset), notice: "Dataset designated as version-type draft."
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  def version_to_draft
    authorize! :review_versions, @dataset

    unless @dataset.draft? && @dataset.hold_state_mode == Dataset::HOLD_TEMP_VERSION
      redirect_to dataset_path(@dataset), alert: "Draft/Version toggle requires a version-type draft dataset."
      return
    end

    @dataset.hold_state = Dataset::HOLD_NONE

    if @dataset.save
      redirect_to dataset_path(@dataset), notice: "Dataset designated as standard draft."
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
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

  private

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
end
