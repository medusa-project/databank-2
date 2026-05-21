class Datafile < ApplicationRecord
  include Datafile::Storable

  WEB_ID_LENGTH = 5

  belongs_to :dataset
  has_one_attached :binary

  validates :web_id,      presence: true, uniqueness: true,
                          format: { with: /\A[a-z0-9]{#{WEB_ID_LENGTH}}\z/ }
  validates :binary_name, presence: true, allow_blank: true

  before_validation :set_web_id, on: :create

  def to_param
    web_id
  end

  def sync_metadata_from_attachment!
    return unless binary.attached?

    self.binary_name = binary.filename.to_s
    self.binary_size = binary.byte_size
  end

  private

  def set_web_id
    self.web_id ||= generate_web_id
  end

  def generate_web_id
    loop do
      candidate = (36**(WEB_ID_LENGTH - 1) + rand(36**WEB_ID_LENGTH - 36**(WEB_ID_LENGTH - 1))).to_s(36)
      break candidate unless self.class.exists?(web_id: candidate)
    end
  end
end
