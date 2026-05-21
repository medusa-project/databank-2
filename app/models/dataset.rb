class Dataset < ApplicationRecord
  KEY_PREFIX = ENV.fetch("DATASET_KEY_PREFIX", "IDB").freeze
  KEY_DIGITS  = 7

  has_many :datafiles,         dependent: :destroy
  has_many :creators,          -> { order(:position, :id) }, dependent: :destroy
  has_many :contributors,      -> { order(:position, :id) }, dependent: :destroy
  has_many :funders,           -> { order(:position, :id) }, dependent: :destroy
  has_many :related_materials, -> { order(:position, :id) }, dependent: :destroy

  enum :publication_state, { draft: 0, published: 1 }, default: :draft

  validates :key,             presence: true, uniqueness: true,
                              format: { with: /\A#{Regexp.escape(KEY_PREFIX)}-\d{#{KEY_DIGITS}}\z/ }
  validates :title,           presence: true
  validates :owner_uid,       presence: true
  validates :depositor_name,  presence: true
  validates :depositor_email, presence: true

  before_validation :set_key, on: :create

  def to_param
    key
  end

  def generate_doi
    "10.5555/#{key}"
  end

  def missing_publish_fields
    missing = []
    missing << "title"            if title.blank?
    missing << "description"      if description.blank?
    missing << "creators"         if creators.empty?
    missing << "contact creator"  if creators.where(contact: true).empty?
    missing << "depositor contact" if depositor_email.blank?
    missing
  end

  def ready_to_publish?
    missing_publish_fields.empty?
  end

  private

  def set_key
    self.key ||= generate_key
  end

  def generate_key
    loop do
      candidate = "#{KEY_PREFIX}-#{rand(10**KEY_DIGITS).to_s.rjust(KEY_DIGITS, '0')}"
      break candidate unless self.class.exists?(key: candidate)
    end
  end
end
