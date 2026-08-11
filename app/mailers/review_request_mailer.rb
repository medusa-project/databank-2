class ReviewRequestMailer < ApplicationMailer
  def review_requested(review_request:, dataset:)
    @review_request = review_request
    @dataset = dataset

    recipients = (CuratorDirectory.review_recipients + [review_request.requester_email, dataset.depositor_email]).uniq

    mail(
      to: recipients,
      subject: "Dataset Consultation Request for #{dataset.key}"
    )
  end
end
