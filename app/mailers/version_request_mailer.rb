class VersionRequestMailer < ApplicationMailer
  def request_submitted(version_request:, dataset:, recipients:)
    @version_request = version_request
    @dataset = dataset

    mail(
      to: recipients,
      subject: "Version request submitted for #{dataset.key}"
    )
  end

  def request_acknowledged(version_request:, dataset:)
    @version_request = version_request
    @dataset = dataset

    mail(
      to: version_request.requester_email,
      subject: "Your version request was received for #{dataset.key}"
    )
  end

  def request_approved(version_request:, dataset:, approved_dataset:)
    @version_request = version_request
    @dataset = dataset
    @approved_dataset = approved_dataset

    mail(
      to: version_request.requester_email,
      subject: "Your version request was approved for #{dataset.key}"
    )
  end
end
