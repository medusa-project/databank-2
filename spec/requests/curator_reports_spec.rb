require "rails_helper"

RSpec.describe "Curator reports", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    OmniAuth.config.test_mode = true
    clear_enqueued_jobs
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  it "allows an admin to request file audit generation" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect do
      post request_file_audit_curator_reports_path, params: { notes: "audit notes" }
    end.to change(CuratorReport, :count).by(1)

    expect(response).to redirect_to(curator_reports_path)
    report = CuratorReport.last
    expect(report.report_type).to eq(CuratorReport::FILE_AUDIT)
    expect(report.requestor_email).to eq("admin@example.edu")
    expect(report.notes).to eq("audit notes")
  end

  it "blocks non-admin users" do
    sign_in_as(email: "depositor@example.edu", name: "Depositor User", role: "depositor")

    get curator_reports_path

    expect(response).to redirect_to(root_path)
  end

  it "downloads generated report content" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    report = CuratorReport.create!(
      requestor_name: "Admin User",
      requestor_email: "admin@example.edu",
      report_type: CuratorReport::FILE_AUDIT,
      storage_root: StorageManager.instance.report_root.name,
      storage_key: "test-report.csv"
    )

    root = StorageManager.instance.root_set.at(report.storage_root)
    root.copy_io_to(report.storage_key, StringIO.new("h1,h2\n1,2\n"), nil, 10)

    get download_curator_report_path(report)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/csv")
    expect(response.body).to include("h1,h2")
  end

  def sign_in_as(email:, name:, role:)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: email,
      info: {
        email: email,
        name: name,
        nickname: email.split("@").first,
        role: role
      }
    )

    get "/auth/developer/callback"
  end
end
