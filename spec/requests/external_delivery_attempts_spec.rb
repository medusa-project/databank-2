require "rails_helper"

RSpec.describe "External delivery attempts index", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  let(:dataset_one) do
    Dataset.create!(
      key: "IDB-6000001",
      title: "Dataset One",
      description: "One",
      owner_uid: "owner-a",
      depositor_name: "Owner A",
      depositor_email: "owner-a@example.edu",
      publication_state: :published,
      published_at: Time.current,
      identifier: "10.5555/IDB-6000001"
    )
  end

  let(:dataset_two) do
    Dataset.create!(
      key: "IDB-6000002",
      title: "Dataset Two",
      description: "Two",
      owner_uid: "owner-b",
      depositor_name: "Owner B",
      depositor_email: "owner-b@example.edu",
      publication_state: :published,
      published_at: Time.current,
      identifier: "10.5555/IDB-6000002"
    )
  end

  it "allows admin to view and filter delivery attempts" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:k1",
      error_message: "Ingest timeout"
    )
    ExternalDeliveryAttempt.create!(
      dataset: dataset_two,
      integration: :globus,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_two.id}:k2"
    )

    get admin_external_delivery_attempts_path, params: {
      dataset_key: dataset_one.key,
      integration: "ingest",
      status: "failed"
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("External Delivery Audit")
    expect(response.body).to include(dataset_one.key)
    expect(response.body).to include("ingest")
    expect(response.body).to include("failed")
    expect(response.body).to include("Ingest timeout")

    expect(response.body).not_to include(dataset_two.key)
  end

  it "allows curator users to view external delivery attempts" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:curator-view",
      error_message: "Curator visible"
    )

    get admin_external_delivery_attempts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("External Delivery Audit")
    expect(response.body).to include(dataset_one.key)
    expect(response.body).to include("Curator visible")
  end

  it "blocks non-admin users" do
    sign_in_as(email: "owner-a@example.edu", name: "Owner A", role: "depositor")

    get admin_external_delivery_attempts_path

    expect(response).to redirect_to(root_path)
  end

  it "supports sorting by integration" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ingest = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:sort-ingest",
      error_message: "ingest-row"
    )
    globus = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :globus,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:sort-globus",
      error_message: "globus-row"
    )

    ingest.update_columns(created_at: Time.current - 10.minutes)
    globus.update_columns(created_at: Time.current - 5.minutes)

    get admin_external_delivery_attempts_path, params: { sort: "integration", direction: "asc", per_page: 20 }

    expect(response).to have_http_status(:ok)
    expect(response.body.index("globus-row")).to be < response.body.index("ingest-row")
  end

  it "supports pagination" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    first_attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:page-1",
      error_message: "first"
    )
    second_attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 2,
      idempotency_key: "dataset.published:#{dataset_one.id}:page-2",
      error_message: "second"
    )

    first_attempt.update_columns(created_at: Time.current - 20.minutes)
    second_attempt.update_columns(created_at: Time.current - 10.minutes)

    get admin_external_delivery_attempts_path, params: {
      dataset_key: dataset_one.key,
      per_page: 1,
      page: 1,
      sort: "created_at",
      direction: "desc"
    }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<td>second</td>")
    expect(response.body).not_to include("<td>first</td>")

    get admin_external_delivery_attempts_path, params: {
      dataset_key: dataset_one.key,
      per_page: 1,
      page: 2,
      sort: "created_at",
      direction: "desc"
    }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<td>first</td>")
    expect(response.body).not_to include("<td>second</td>")
  end

  it "exports filtered attempts as csv" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:csv-1",
      error_message: "csv-ingest"
    )
    ExternalDeliveryAttempt.create!(
      dataset: dataset_two,
      integration: :globus,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_two.id}:csv-2",
      error_message: "csv-globus"
    )

    get admin_external_delivery_attempts_path(format: :csv), params: {
      dataset_key: dataset_one.key,
      integration: "ingest"
    }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    expect(response.body).to include("dataset_key,integration,event_name,status")
    expect(response.body).to include(dataset_one.key)
    expect(response.body).to include("csv-ingest")
    expect(response.body).not_to include(dataset_two.key)
    expect(response.body).not_to include("csv-globus")
  end

  it "allows admin to replay a single failed ingest attempt" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:single-replay"
    )

    post replay_admin_external_delivery_attempt_path(attempt)

    expect(response).to have_http_status(:redirect)
    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    expect(ingest_jobs.map { |job| job[:args] }).to include([ dataset_one.id, attempt.idempotency_key ])
  end

  it "blocks replay of ingest attempt already acknowledged by response unless forced" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:guardrail-single"
    )

    post replay_admin_external_delivery_attempt_path(attempt)

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("Replay blocked: ingest response is already acknowledged as succeeded")
    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    expect(ingest_jobs).to be_empty
  end

  it "allows forced replay of ingest attempt acknowledged by response" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:guardrail-force"
    )

    post replay_admin_external_delivery_attempt_path(attempt), params: { force_replay: true }

    expect(response).to have_http_status(:redirect)
    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    expect(ingest_jobs.map { |job| job[:args] }).to include([ dataset_one.id, attempt.idempotency_key ])
  end

  it "does not replay non-failed attempts" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :globus,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:already-ok"
    )

    post replay_admin_external_delivery_attempt_path(attempt)

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("Only failed attempts can be replayed.")
  end

  it "replays selected failed attempts in bulk" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    failed_ingest = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:bulk-ingest"
    )
    failed_globus = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :globus,
      event_name: "dataset.published",
      status: :failed,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:bulk-globus"
    )
    succeeded_attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:bulk-skip"
    )

    post replay_selected_admin_external_delivery_attempts_path, params: {
      attempt_ids: [ failed_ingest.id, failed_globus.id, succeeded_attempt.id ]
    }

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("Replayed 2 selected failed attempt")

    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    globus_jobs = enqueued_jobs.select { |job| job[:job] == Globus::SubmitDatasetTransferJob }

    expect(ingest_jobs.map { |job| job[:args] }).to include([ dataset_one.id, failed_ingest.idempotency_key ])
    expect(globus_jobs.map { |job| job[:args] }).to include([ dataset_one.id, failed_globus.idempotency_key ])
  end

  it "blocks bulk replay for response-acknowledged ingest attempts unless forced" do
    clear_enqueued_jobs
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    blocked_attempt = ExternalDeliveryAttempt.create!(
      dataset: dataset_one,
      integration: :ingest,
      event_name: "dataset.published",
      status: :failed,
      response_status: :succeeded,
      attempt: 1,
      idempotency_key: "dataset.published:#{dataset_one.id}:bulk-guardrail"
    )

    post replay_selected_admin_external_delivery_attempts_path, params: {
      attempt_ids: [ blocked_attempt.id ]
    }

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("No selected attempts were replayed because ingest response guardrails blocked")
    ingest_jobs = enqueued_jobs.select { |job| job[:job] == Ingest::PublishDatasetEventJob }
    expect(ingest_jobs).to be_empty
  end

  it "alerts when no attempts are selected for bulk replay" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    post replay_selected_admin_external_delivery_attempts_path

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("No attempts were selected for replay.")
  end

  it "shows orphaned ingest responses on the audit page" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    IngestResponseEvent.create!(
      status: :unmatched,
      integration: "ingest",
      correlation_key: "missing-correlation",
      received_at: Time.current,
      payload: { status: "ok" },
      raw_payload: "{\"status\":\"ok\"}",
      error_message: "No matching delivery attempt"
    )

    get admin_external_delivery_attempts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Orphaned Ingest Responses")
    expect(response.body).to include("missing-correlation")
    expect(response.body).to include("No matching delivery attempt")
  end

  it "allows admin to acknowledge orphaned ingest responses" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    orphan_event = IngestResponseEvent.create!(
      status: :unmatched,
      integration: "ingest",
      correlation_key: "dataset.published:#{dataset_one.id}:orphan-ack",
      received_at: Time.current,
      payload: { status: "ok" },
      raw_payload: "{\"status\":\"ok\"}",
      error_message: "No matching delivery attempt"
    )

    post acknowledge_admin_ingest_response_event_path(orphan_event)

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("Orphaned ingest response acknowledged.")

    orphan_event.reload
    expect(orphan_event.acknowledged_at).to be_present
    expect(orphan_event.acknowledged_by_email).to eq("admin@example.edu")

    get admin_external_delivery_attempts_path
    expect(response.body).not_to include("dataset.published:#{dataset_one.id}:orphan-ack")
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
