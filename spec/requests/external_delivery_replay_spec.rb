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

  it "blocks dataset-level replay for response-acknowledged ingest failures unless forced" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ingest_key = "dataset.published:#{dataset.id}:acknowledged"
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :succeeded,
      attempt: 1,
      idempotency_key: ingest_key
    )

    post replay_failed_deliveries_dataset_path(dataset), params: { integration: "ingest" }

    expect(response).to redirect_to(dataset_path(dataset))
    follow_redirect!
    expect(response.body).to include("acknowledged ingest attempt(s) were blocked")
    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    expect(ingest_jobs).to be_empty
  end

  it "allows forced dataset-level replay for response-acknowledged ingest failures" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ingest_key = "dataset.published:#{dataset.id}:acknowledged-force"
    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :succeeded,
      attempt: 1,
      idempotency_key: ingest_key
    )

    post replay_failed_deliveries_dataset_path(dataset), params: { integration: "ingest", force_replay: true }

    expect(response).to redirect_to(dataset_path(dataset))
    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    expect(ingest_jobs.map { |job| job[:args] }).to include([ dataset.id, ingest_key ])
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
    expect(response.body).to include("Ingest Response Health")
    expect(response.body).to include("ingest: failed")
    expect(response.body).to include("Replay All Failed Deliveries")
    expect(response.body).to include("Force Replay All Failed Deliveries")
    expect(response.body).to include("Replay ingest Failures")
    expect(response.body).to include("Force Replay ingest Failures")
  end

  it "shows stale response and orphan warnings when thresholds are exceeded" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ExternalDeliveryAttempt.create!(
      dataset: dataset,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :succeeded,
      response_received_at: 3.hours.ago,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset.id}:health-stale"
    )

    IngestResponseEvent.create!(
      status: :unmatched,
      integration: "ingest",
      correlation_key: "dataset.published:#{dataset.id}:orphan-1",
      received_at: Time.current,
      payload: { status: "ok" },
      raw_payload: "{\"status\":\"ok\"}",
      error_message: "No matching delivery attempt"
    )

    get dataset_path(dataset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Status: Warning")
    expect(response.body).to include("Latest Medusa response is stale")
    expect(response.body).to include("orphaned ingest response(s) in the last")
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
