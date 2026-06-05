class DatasetAccessGrant < ApplicationRecord
  belongs_to :dataset

  enum :access_level, { viewer: 0, editor: 1 }

  before_validation :normalize_email

  validates :email, presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { scope: :dataset_id, case_sensitive: false }

  scope :for_email, ->(email) do
    normalized_email = normalize_email_value(email)
    normalized_email.present? ? where(email: normalized_email) : none
  end

  def self.normalize_email_value(email)
    email.to_s.strip.downcase.presence
  end

  def self.grants_read_access?(dataset_id:, email:)
    for_email(email).where(dataset_id: dataset_id).exists?
  end

  def self.grants_edit_access?(dataset_id:, email:)
    for_email(email).where(dataset_id: dataset_id, access_level: :editor).exists?
  end

  private

  def normalize_email
    self.email = self.class.normalize_email_value(email)
  end
end
