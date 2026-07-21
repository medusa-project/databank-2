class User < ApplicationRecord
  ROLES = %w[depositor curator admin guest no_deposit].freeze

  validates :provider, presence: true
  validates :uid,      presence: true, uniqueness: { scope: :provider }
  validates :email,    presence: true, uniqueness: true
  validates :role,     inclusion: { in: ROLES }

  def self.from_omniauth(auth)
    return unless auth && auth[:uid]

    user = User.find_by(provider: auth["provider"], uid: auth["uid"])
    if user
      user.update_with_omniauth(auth)
    else
      user = User.create_with_omniauth(auth)
    end
    user
  end

  def self.guest
    new(role: "guest")
  end

  def admin?
    role == "admin" || config_admin?
  end

  def curator?
    return true if admin? || role == "curator"
    return false if email.blank?

    CuratorDirectory.includes_email?(email)
  end

  def depositor?
    return true if role == "depositor"
    return false if email.blank?

    ManagedDepositException.exists?(email: email.strip.downcase)
  end

  def self.create_with_omniauth(auth)
    auth["info"]["role"] = User.user_role(auth) if auth["provider"] == "shibboleth"
    create! do |user|
      user.provider = auth["provider"]
      user.uid = auth["uid"]
      user.email = auth["info"]["email"]
      user.username = auth["info"]["email"].split("@").first
      user.name = auth["info"]["name"]
      user.role = auth["info"]["role"].presence || "depositor"
    end
  end

  def update_with_omniauth(auth)
    auth["info"]["role"] = User.user_role(auth) if auth["provider"] == "shibboleth"
    update_attribute(:provider, auth["provider"]) # rubocop:disable Rails/SkipsModelValidations
    update_attribute(:uid, auth["uid"]) # rubocop:disable Rails/SkipsModelValidations
    update_attribute(:email, auth["info"]["email"]) # rubocop:disable Rails/SkipsModelValidations
    update_attribute(:username, email.split("@").first) # rubocop:disable Rails/SkipsModelValidations
    update_attribute(:name, auth["info"]["name"]) # rubocop:disable Rails/SkipsModelValidations
    update_attribute(:role, auth["info"]["role"].presence || role || "depositor") # rubocop:disable Rails/SkipsModelValidations
    self
  end

  def self.user_role(auth)
    affiliations = auth.dig("extra", "raw_info", "iTrustAffiliation")
    return "no_deposit" unless affiliations.respond_to?(:split)

    affiliation_list = affiliations.split(";")
    return "depositor" if affiliation_list.include?("staff")

    if affiliation_list.include?("student")
      level_code = auth.dig("extra", "raw_info", "uiucEduStudentLevelCode")
      return level_code == "1U" ? "no_deposit" : "depositor"
    end

    "no_deposit"
  rescue StandardError
    "no_deposit"
  end

  def config_admin?
    self.class.config_admin?(uid: uid, email: email, username: username)
  end

  def self.config_admin?(uid:, email:, username: nil)
    identifiers = normalized_admin_identifiers(uid: uid, email: email, username: username)
    return false if identifiers.empty?

    (configured_admin_netids + configured_admin_emails).any? do |configured_identifier|
      identifiers.include?(configured_identifier)
    end
  end

  def self.configured_admin_netids
    raw_netids = IdbConfig.fetch(:admin, :netids, default: "")

    raw_netids.to_s.split(",").map { |value| normalize_admin_identifier(value) }.reject(&:blank?).uniq
  end

  def self.configured_admin_emails
    configured_admin_netids.map { |netid| illinois_email_for(netid) }
  end

  def self.normalized_admin_identifiers(uid:, email:, username: nil)
    [ uid, email, username, illinois_email_for(username) ]
      .map { |value| normalize_admin_identifier(value) }
      .reject(&:blank?)
      .uniq
  end

  def self.normalize_admin_identifier(value)
    value.to_s.strip.downcase
  end

  def self.illinois_email_for(netid)
    normalized_netid = normalize_admin_identifier(netid)
    return "" if normalized_netid.blank?
    return normalized_netid if normalized_netid.include?("@")

    "#{normalized_netid}@illinois.edu"
  end
end
