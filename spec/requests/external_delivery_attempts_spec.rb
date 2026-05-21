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

    get admin_external_delivery_attempts_path, params: { per_page: 1, page: 1, sort: "created_at", direction: "desc" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("second")
    expect(response.body).not_to include("first")

    get admin_external_delivery_attempts_path, params: { per_page: 1, page: 2, sort: "created_at", direction: "desc" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("first")
    expect(response.body).not_to include("second")
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
