require "securerandom"

class Token < ApplicationRecord
  belongs_to :dataset, primary_key: :key, foreign_key: :dataset_key, inverse_of: :token

  validates :dataset_key, presence: true
  validates :identifier, presence: true
  validates :dataset_key, uniqueness: true
  validates :identifier, uniqueness: true

  def self.generate_auth_token
    SecureRandom.uuid.delete("-")
  end
end
