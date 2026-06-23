require "rails_helper"

RSpec.describe VersionRequestNotificationService, type: :service do
  let(:dataset) { create(:dataset) }
  let(:approved_dataset) { create(:dataset) }
  let(:version_request) do
    VersionRequest.create!(
      dataset: dataset,
      requester_email: "requester@example.edu",
      requester_name: "Requester",
      requested_at: Time.current
    )
  end

  before do
    allow(IdbConfig).to receive(:fetch).and_call_original
  end

  it "sends curator and requester emails when recipients are configured" do
    submitted_mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    acknowledged_mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)

    allow(IdbConfig).to receive(:fetch).with(:version_request, :review_emails, default: "").and_return("one@example.edu, two@example.edu")
    allow(VersionRequestMailer).to receive(:request_submitted).and_return(submitted_mail)
    allow(VersionRequestMailer).to receive(:request_acknowledged).and_return(acknowledged_mail)

    described_class.request_submitted(version_request: version_request, dataset: dataset)

    expect(VersionRequestMailer).to have_received(:request_submitted).with(version_request: version_request, dataset: dataset, recipients: [ "one@example.edu", "two@example.edu" ])
    expect(VersionRequestMailer).to have_received(:request_acknowledged).with(version_request: version_request, dataset: dataset)
  end

  it "falls back to curator directory recipients when config is blank" do
    submitted_mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    acknowledged_mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)

    allow(IdbConfig).to receive(:fetch).with(:version_request, :review_emails, default: "").and_return("  ")
    allow(CuratorDirectory).to receive(:review_recipients).and_return([ "curator@example.edu" ])
    allow(VersionRequestMailer).to receive(:request_submitted).and_return(submitted_mail)
    allow(VersionRequestMailer).to receive(:request_acknowledged).and_return(acknowledged_mail)

    described_class.new.request_submitted(version_request: version_request, dataset: dataset)

    expect(VersionRequestMailer).to have_received(:request_submitted).with(version_request: version_request, dataset: dataset, recipients: [ "curator@example.edu" ])
  end

  it "still acknowledges the requester when there are no curator recipients" do
    acknowledged_mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)

    allow(IdbConfig).to receive(:fetch).with(:version_request, :review_emails, default: "").and_return("")
    allow(CuratorDirectory).to receive(:review_recipients).and_return([])
    allow(VersionRequestMailer).to receive(:request_acknowledged).and_return(acknowledged_mail)
    allow(VersionRequestMailer).to receive(:request_submitted)

    described_class.request_submitted(version_request: version_request, dataset: dataset)

    expect(VersionRequestMailer).not_to have_received(:request_submitted)
    expect(VersionRequestMailer).to have_received(:request_acknowledged)
  end

  it "logs and swallows submission failures" do
    allow(IdbConfig).to receive(:fetch).with(:version_request, :review_emails, default: "").and_return("curator@example.edu")
    allow(VersionRequestMailer).to receive(:request_submitted).and_raise(StandardError.new("boom"))
    allow(Rails.logger).to receive(:warn)

    expect do
      described_class.request_submitted(version_request: version_request, dataset: dataset)
    end.not_to raise_error

    expect(Rails.logger).to have_received(:warn).with(/version request submission mail failed for dataset #{dataset.key}/)
  end

  it "sends the approval email" do
    approved_mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(VersionRequestMailer).to receive(:request_approved).and_return(approved_mail)

    described_class.request_approved(version_request: version_request, dataset: dataset, approved_dataset: approved_dataset)

    expect(VersionRequestMailer).to have_received(:request_approved).with(version_request: version_request, dataset: dataset, approved_dataset: approved_dataset)
  end

  it "logs and swallows approval failures" do
    allow(VersionRequestMailer).to receive(:request_approved).and_raise(StandardError.new("boom"))
    allow(Rails.logger).to receive(:warn)

    expect do
      described_class.request_approved(version_request: version_request, dataset: dataset, approved_dataset: approved_dataset)
    end.not_to raise_error

    expect(Rails.logger).to have_received(:warn).with(/version request approval mail failed for dataset #{dataset.key}/)
  end
end
