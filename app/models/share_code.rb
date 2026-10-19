require "securerandom"

class ShareCode < ApplicationRecord
  belongs_to :dataset

  before_validation :set_code, on: :create

  validates :code, presence: true, uniqueness: true
  validates :dataset_id, uniqueness: true

  def set_code
    self.code ||= generate_code
  end

  def generate_code
    loop do
      proposed_code = SecureRandom.urlsafe_base64(32, false)
      return proposed_code unless self.class.exists?(code: proposed_code)
    end
  end
end
