require "rails_helper"

RSpec.describe "External delivery replay", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  let(:dataset) do
    Dataset.create!(
      key: "IDB-5888888",
      title: "Replay Dataset",
      description: "Replay testing",
      owner_uid: "owner-replay",
      depositor_name: "Owner Replay",
      depositor_email: "owner-replay@example.edu",
      publication_state: :published,
      published_at: Time.current,
      identifier: "10.5555/IDB-5888888"
    )
  end

  it "allows admin to replay failed ingest and globus attempts" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ingest_key = "dataset.published:#{dataset.id}:k1"
    globus_key = "dataset.published:#{dataset.id}:k2"

    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: ingest_key
    )
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :globus,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: globus_key
    )

    post replay_failed_deliveries_dataset_path(dataset)

    expect(response).to redirect_to(dataset_path(dataset))

    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    globus_jobs = enqueued_jobs.select { |job| job[:job] == Globus::SubmitDatasetTransferJob }

    expect(ingest_jobs.map { |job| job[:args] }).to include([ dataset.id, ingest_key ])
    expect(globus_jobs.map { |job| job[:args] }).to include([ dataset.id, globus_key ])
  end

  it "replays only selected integration failures" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ingest_key = "dataset.published:#{dataset.id}:only-ingest"
    globus_key = "dataset.published:#{dataset.id}:only-globus"

    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: ingest_key
    )
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :globus,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: globus_key
    )

    post replay_failed_deliveries_dataset_path(dataset), params: { integration: "ingest" }

    expect(response).to redirect_to(dataset_path(dataset))

    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    globus_jobs = enqueued_jobs.select { |job| job[:job] == Globus::SubmitDatasetTransferJob }

    expect(ingest_jobs.map { |job| job[:args] }).to include([ dataset.id, ingest_key ])
    expect(globus_jobs).to be_empty
  end

  it "shows external delivery status panel on dataset page for admins" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 2,
      idempotency_key: "dataset.published:#{dataset.id}:panel",
      error_message: "Publisher timeout"
    )

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("External Delivery")
    expect(response.body).to include("ingest: failed")
    expect(response.body).to include("Replay All Failed Deliveries")
    expect(response.body).to include("Replay ingest Failures")
  end

  it "blocks non-admin replay attempts" do
    sign_in_as(email: "owner-replay@example.edu", name: "Owner Replay", role: "depositor")

    post replay_failed_deliveries_dataset_path(dataset)

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name,
        nickname: email,
        role: role
      }
    )

    get "/auth/developer/callback"
    expect(response).to have_http_status(:redirect)
  end
end
