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
end
