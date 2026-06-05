class IngestHealthMailer < ApplicationMailer
  def dataset_alert(dataset:, summary:, recipients:)
    @dataset = dataset
    @summary = summary

    mail(
      to: recipients,
      subject: "Ingest health alert for #{@dataset.key}"
    )
  end
end
