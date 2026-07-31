require "rails_helper"

RSpec.describe "Admin page", type: :request do
  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:developer] = nil
  end

  before do
    ManagedCurator.delete_all
    ManagedDepositException.delete_all
    AppSetting.delete_all
    allow(CuratorDirectory).to receive(:core_emails).and_return([ "core.curator@example.edu" ])
  end

  it "shows curator/admin page link on welcome page for admins only" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Curator and Admin Tools")

    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Curator and Admin Tools")
    expect(response.body).to include("Change role")
  end

  it "allows admins and curators to access admin page" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    get admin_path
    expect(response).to have_http_status(:ok)

    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")

    get admin_path
    expect(response).to have_http_status(:ok)
  end

  it "treats configured legacy admin netids as admin and curator-capable" do
    allow(IdbConfig).to receive(:fetch).with(:admin, :netids, default: "").and_return("alpha")

    sign_in_as(email: "alpha@illinois.edu", name: "Alpha User", role: "depositor", uid: "alpha")

    get admin_path
    expect(response).to have_http_status(:ok)

    get curator_guide_path
    expect(response).to have_http_status(:ok)
  end

  it "allows admin to add and remove admin-managed curators" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect {
      post admin_managed_curators_path, params: {
        managed_curator: { email: "extra.curator@example.edu" }
      }
    }.to change(ManagedCurator, :count).by(1)

    curator = ManagedCurator.find_by!(email: "extra.curator@example.edu")

    expect {
      delete admin_managed_curator_path(curator)
    }.to change(ManagedCurator, :count).by(-1)
  end

  it "does not add duplicate record for configured core curator email" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect {
      post admin_managed_curators_path, params: {
        managed_curator: { email: "core.curator@example.edu" }
      }
    }.not_to change(ManagedCurator, :count)

    follow_redirect!
    expect(response.body).to include("already a core curator")
  end

  it "allows admin to add and remove admin-managed deposit exceptions" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    expect {
      post admin_managed_deposit_exceptions_path, params: {
        managed_deposit_exception: { email: "special.depositor@example.edu" }
      }
    }.to change(ManagedDepositException, :count).by(1)

    managed_exception = ManagedDepositException.find_by!(email: "special.depositor@example.edu")

    expect {
      delete admin_managed_deposit_exception_path(managed_exception)
    }.to change(ManagedDepositException, :count).by(-1)
  end

  it "allows admin to set system-wide message and displays it on welcome page" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")

    patch update_admin_system_message_path, params: {
      admin_page: { system_message: "Planned maintenance tonight" }
    }

    expect(response).to redirect_to(admin_path)
    expect(AppSetting.system_message).to eq("Planned maintenance tonight")

    get root_path
    expect(response.body).to include("Planned maintenance tonight")
  end

  it "allows admin to clear the Rails cache" do
    sign_in_as(email: "admin@example.edu", name: "Admin User", role: "admin")
    allow(Rails.cache).to receive(:clear).and_return(true)

    post clear_admin_cache_path

    expect(Rails.cache).to have_received(:clear)
    expect(response).to redirect_to(admin_path)
    follow_redirect!
    expect(response.body).to include("Rails cache cleared successfully.")
  end

  it "allows curator to clear the Rails cache" do
    sign_in_as(email: "curator@example.edu", name: "Curator User", role: "curator")
    allow(Rails.cache).to receive(:clear).and_return(true)

    post clear_admin_cache_path

    expect(Rails.cache).to have_received(:clear)
    expect(response).to redirect_to(admin_path)
  end

  it "allows admin-managed curator email to receive curator-level access" do
    ManagedCurator.create!(email: "managed.curator@example.edu")
    source = Dataset.create!(
      title: "Managed Curator Source",
      description: "Published source dataset.",
      keywords: "v1",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-version",
      depositor_name: "Owner User",
      depositor_email: "owner@example.edu",
      publication_state: :published,
      identifier: "10.5555/IDB-9900411"
    )

    sign_in_as(email: "managed.curator@example.edu", name: "Managed Curator", role: "depositor")

    get version_controls_dataset_path(source)
    expect(response).to have_http_status(:ok)
  end

  def sign_in_as(email:, name:, role:, uid: email)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer",
      uid: uid,
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
