module DatasetsController::Publishable
  extend ActiveSupport::Concern

  def confirm_review
    authorize! :update, @dataset
  end

  def request_review
    authorize! :update, @dataset
    @dataset.update_column(:identifier, @dataset.generate_doi) if @dataset.identifier.blank?
    review_request = ReviewRequest.create!(
      dataset: @dataset,
      requester_name: current_user.name,
      requester_email: current_user.email,
      requested_at: Time.zone.now
    )
    ReviewRequestMailer.review_requested(review_request: review_request, dataset: @dataset).deliver_now
    redirect_to confirm_review_dataset_path(@dataset), status: :see_other
  end

  def publish
    authorize! :update, @dataset

    if @dataset.draft? && @dataset.hold_state_mode == Dataset::HOLD_TEMP_VERSION
      redirect_to dataset_path(@dataset), alert: "Version drafts require pre-publication review before publishing."
      return
    end

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

  def suppression_controls
    authorize! :manage, @dataset
    @title = "Suppression Controls"
  end

  def suppression_action
    authorize! :manage, @dataset

    action = params[:suppression_action].to_s
    unless suppression_actions.include?(action)
      redirect_to suppression_controls_dataset_path(@dataset), alert: "Unknown suppression action."
      return
    end

    case action
    when "suppress_changelog"
      suppress_changelog
    when "unsuppress_changelog"
      unsuppress_changelog
    when "temporarily_suppress_files"
      temporarily_suppress_files
    when "temporarily_suppress_metadata"
      temporarily_suppress_metadata
    when "unsuppress"
      unsuppress
    when "permanently_suppress_files"
      permanently_suppress_files
    when "permanently_suppress_metadata"
      permanently_suppress_metadata
    when "suppress_review"
      suppress_review
    when "unsuppress_review"
      unsuppress_review
    end
  end

  def suppress_changelog
    authorize! :manage, @dataset

    if @dataset.respond_to?(:suppress_changelog=)
      @dataset.suppress_changelog = true
      if @dataset.save
        redirect_to dataset_path(@dataset), notice: "Dataset changelog has suppressed."
      else
        redirect_to dataset_path(@dataset), alert: "Error - see log."
      end
    else
      redirect_to dataset_path(@dataset), alert: "Suppress changelog is not available in this deployment."
    end
  end

  def unsuppress_changelog
    authorize! :manage, @dataset

    if @dataset.respond_to?(:suppress_changelog=)
      @dataset.suppress_changelog = false
      if @dataset.save
        redirect_to dataset_path(@dataset), notice: "Dataset changelog has been unsuppressed."
      else
        redirect_to dataset_path(@dataset), alert: "Error - see log."
      end
    else
      redirect_to dataset_path(@dataset), alert: "Suppress changelog is not available in this deployment."
    end
  end

  def temporarily_suppress_files
    authorize! :manage, @dataset
    @dataset.hold_state = Dataset::HOLD_TEMP_FILE

    if @dataset.save
      redirect_to dataset_path(@dataset), notice: "Dataset files have been temporarily suppressed."
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  def temporarily_suppress_metadata
    authorize! :manage, @dataset
    @dataset.hold_state = Dataset::HOLD_TEMP_METADATA

    if @dataset.save
      if doi_suppression_service.suppress_metadata
        redirect_to dataset_path(@dataset), notice: "Dataset metadata and files have been temporarily suppressed."
      else
        redirect_to dataset_path(@dataset), notice: "Dataset metadata and files have been temporarily suppressed in IDB, but DataCite was not updated."
      end
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  def unsuppress
    authorize! :manage, @dataset
    @dataset.hold_state = Dataset::HOLD_NONE

    if @dataset.save
      if doi_suppression_service.unsuppress_metadata
        redirect_to dataset_path(@dataset), notice: "Dataset has been unsuppressed."
      else
        redirect_to dataset_path(@dataset), notice: "Dataset has been unsuppressed in IDB, but DataCite was not updated."
      end
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  def permanently_suppress_files
    authorize! :manage, @dataset
    @dataset.hold_state = Dataset::HOLD_PERM_FILE
    @dataset.embargo = Dataset::EMBARGO_NONE
    @dataset.tombstone_date = Date.current

    if @dataset.save
      if globus_suppression_service.remove_from_public_download
        redirect_to dataset_path(@dataset), notice: "Dataset files have been permanently suppressed."
      else
        redirect_to dataset_path(@dataset), notice: "Failed to remove from Globus Download."
      end
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  def suppress_review
    authorize! :manage, @dataset
    @dataset.hold_state = Dataset::HOLD_TEMP_VERSION

    if @dataset.save
      redirect_to dataset_path(@dataset), notice: "Dataset version candidate under curator review."
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  def unsuppress_review
    authorize! :manage, @dataset
    @dataset.hold_state = Dataset::HOLD_NONE

    if @dataset.save
      redirect_to dataset_path(@dataset), notice: "Dataset released for pre-publication review."
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  def permanently_suppress_metadata
    authorize! :manage, @dataset
    @dataset.hold_state = Dataset::HOLD_PERM_METADATA
    @dataset.embargo = Dataset::EMBARGO_NONE
    @dataset.tombstone_date = Date.current

    if @dataset.save
      doi_ok = doi_suppression_service.suppress_metadata
      globus_ok = globus_suppression_service.remove_from_public_download

      if doi_ok && globus_ok
        redirect_to dataset_path(@dataset), notice: "Dataset has been permanently supressed in Illinois Data Bank and DataCite."
      else
        redirect_to dataset_path(@dataset), alert: "Failed to remove from DataCite or Globus Download."
      end
    else
      redirect_to dataset_path(@dataset), alert: "Error - see log."
    end
  end

  private

  def suppression_actions
    %w[
      suppress_changelog
      unsuppress_changelog
      temporarily_suppress_files
      temporarily_suppress_metadata
      unsuppress
      permanently_suppress_files
      permanently_suppress_metadata
      suppress_review
      unsuppress_review
    ]
  end

  def doi_suppression_service
    @doi_suppression_service ||= Doi::SuppressionService.new(@dataset)
  end

  def globus_suppression_service
    @globus_suppression_service ||= Globus::SuppressionService.new(@dataset)
  end
end
