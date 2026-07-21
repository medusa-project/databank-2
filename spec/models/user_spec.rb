require "rails_helper"

RSpec.describe User, type: :model do
  def auth_hash(provider: "developer", uid: "user-1", email: "user@example.edu", name: "Example User", role: "depositor", extra: {})
    OmniAuth::AuthHash.new(
      "provider" => provider,
      "uid" => uid,
      "info" => {
        "email" => email,
        "name" => name,
        "role" => role
      },
      "extra" => extra
    )
  end

  it "defines the expected role list" do
    expect(described_class::ROLES).to eq(%w[depositor curator admin guest no_deposit])
  end

  it "builds a guest user" do
    guest = described_class.guest

    expect(guest).to be_a(described_class)
    expect(guest.role).to eq("guest")
    expect(guest).not_to be_persisted
  end

  it "recognizes admin users" do
    expect(build(:user, role: "admin")).to be_admin
    expect(build(:user, role: "curator")).not_to be_admin
  end

  it "treats configured legacy admin netids as admin users" do
    allow(IdbConfig).to receive(:fetch).with(:admin, :netids, default: "").and_return("alpha, beta")

    expect(build(:user, role: "depositor", uid: "alpha", email: "alpha@illinois.edu")).to be_admin
    expect(build(:user, role: "depositor", uid: "gamma", email: "beta@illinois.edu")).to be_admin
  end

  it "treats admin and curator roles as curator-capable" do
    expect(build(:user, role: "admin")).to be_curator
    expect(build(:user, role: "curator")).to be_curator
  end

  it "treats configured legacy admin netids as curator-capable" do
    allow(IdbConfig).to receive(:fetch).with(:admin, :netids, default: "").and_return("alpha")

    expect(build(:user, role: "depositor", uid: "alpha", email: "alpha@illinois.edu")).to be_curator
  end

  it "checks curator access by email when role alone is insufficient" do
    user = build(:user, role: "depositor", email: "curator@example.edu")

    allow(CuratorDirectory).to receive(:includes_email?).with("curator@example.edu").and_return(true)

    expect(user).to be_curator
  end

  it "does not treat blank-email users as curators or depositors" do
    user = build(:user, role: "guest", email: nil)

    expect(user).not_to be_curator
    expect(user).not_to be_depositor
  end

  it "treats depositor role and managed exceptions as depositor-capable" do
    direct_depositor = build(:user, role: "depositor")
    exception_user = build(:user, role: "no_deposit", email: " Exception@example.edu ")

    ManagedDepositException.create!(email: "exception@example.edu")

    expect(direct_depositor).to be_depositor
    expect(exception_user).to be_depositor
  end

  it "returns nil from omniauth when the auth payload is missing or lacks a uid" do
    expect(described_class.from_omniauth(nil)).to be_nil
    expect(described_class.from_omniauth({ "provider" => "developer" })).to be_nil
  end

  it "creates a new user from omniauth when one does not exist" do
    auth = auth_hash(uid: "new-user", email: "new.user@example.edu", name: "New User")

    user = described_class.from_omniauth(auth)

    expect(user).to be_persisted
    expect(user.provider).to eq("developer")
    expect(user.uid).to eq("new-user")
    expect(user.email).to eq("new.user@example.edu")
    expect(user.username).to eq("new.user")
    expect(user.name).to eq("New User")
    expect(user.role).to eq("depositor")
  end

  it "updates an existing user from omniauth" do
    user = create(:user, provider: "developer", uid: "existing-user", email: "old@example.edu", username: "old", name: "Old Name", role: "guest")
    auth = auth_hash(uid: "existing-user", email: "updated@example.edu", name: "Updated Name", role: "curator")

    returned_user = described_class.from_omniauth(auth)

    expect(returned_user.id).to eq(user.id)
    expect(user.reload.email).to eq("updated@example.edu")
    expect(user.username).to eq("updated")
    expect(user.name).to eq("Updated Name")
    expect(user.role).to eq("curator")
  end

  it "derives the role from shibboleth auth when creating a user" do
    auth = auth_hash(
      provider: "shibboleth",
      uid: "shib-user",
      email: "shib@example.edu",
      role: nil,
      extra: {
        "raw_info" => {
          "iTrustAffiliation" => "faculty;staff"
        }
      }
    )

    user = described_class.create_with_omniauth(auth)

    expect(user.role).to eq("depositor")
    expect(user.username).to eq("shib")
  end

  it "preserves the existing role when updating and the new auth role is blank" do
    user = create(:user, provider: "developer", uid: "existing-user", email: "old@example.edu", username: "old", name: "Old Name", role: "curator")
    auth = auth_hash(uid: "existing-user", email: "still.old@example.edu", name: "Still Old", role: nil)

    user.update_with_omniauth(auth)

    expect(user.reload.role).to eq("curator")
    expect(user.email).to eq("still.old@example.edu")
    expect(user.username).to eq("still.old")
  end

  it "resolves staff and eligible student shibboleth roles to depositor" do
    staff_auth = auth_hash(extra: { "raw_info" => { "iTrustAffiliation" => "member;staff" } })
    graduate_auth = auth_hash(extra: { "raw_info" => { "iTrustAffiliation" => "member;student", "uiucEduStudentLevelCode" => "GR" } })

    expect(described_class.user_role(staff_auth)).to eq("depositor")
    expect(described_class.user_role(graduate_auth)).to eq("depositor")
  end

  it "resolves undergraduate students and malformed shibboleth data to no_deposit" do
    undergraduate_auth = auth_hash(extra: { "raw_info" => { "iTrustAffiliation" => "member;student", "uiucEduStudentLevelCode" => "1U" } })
    malformed_auth = auth_hash(extra: { "raw_info" => { "iTrustAffiliation" => Object.new } })

    expect(described_class.user_role(undergraduate_auth)).to eq("no_deposit")
    expect(described_class.user_role(malformed_auth)).to eq("no_deposit")
  end
end
