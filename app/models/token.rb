require "securerandom"

class Token < ApplicationRecord
  validates :dataset_key, presence: true
  validates :identifier, presence: true

  def self.generate_auth_token
    SecureRandom.uuid.delete("-")
  end
end
