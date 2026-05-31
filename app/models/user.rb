class User < ApplicationRecord
  ROLES = %w[depositor curator admin].freeze

  validates :provider, presence: true
  validates :uid,      presence: true, uniqueness: { scope: :provider }
  validates :email,    presence: true, uniqueness: true
  validates :role,     inclusion: { in: ROLES }

  def self.from_omniauth(auth)
    find_or_initialize_by(provider: auth.provider, uid: auth.uid).tap do |user|
      user.email    = auth.info.email
      user.name     = auth.info.name
      user.username = auth.info.nickname.presence || auth.info.email
      user.role     = auth.info.role.presence || auth.extra&.dig(:raw_info, :role).presence || user.role || "depositor"
      user.save!
    end
  end

  def self.guest
    new(role: "depositor")
  end

  def admin?
    role == "admin"
  end

  def curator?
    return true if admin? || role == "curator"
    return false if email.blank?

    CuratorDirectory.includes_email?(email)
  end

  def depositor?
    role == "depositor"
  end
end
