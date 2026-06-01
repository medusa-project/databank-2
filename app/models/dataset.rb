class Dataset < ApplicationRecord
  KEY_PREFIX = ENV.fetch("DATASET_KEY_PREFIX", "IDB").freeze
  KEY_DIGITS = 7
  EMBARGO_NONE = "none".freeze
  EMBARGO_FILE = "file".freeze
  EMBARGO_METADATA = "metadata".freeze
  EMBARGO_OPTIONS = [ EMBARGO_NONE, EMBARGO_FILE, EMBARGO_METADATA ].freeze
  CREATOR_TYPE_PERSON = 0
  CREATOR_TYPE_INSTITUTION = 1

  has_many :datafiles,         dependent: :destroy
  has_many :creators,          -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :contributors,      -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :funders,           -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :notes,             -> { order(created_at: :desc, id: :desc) }, dependent: :destroy
  has_many :related_materials, -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :version_requests, dependent: :destroy
  has_many :approved_version_requests, class_name: "VersionRequest", foreign_key: :approved_dataset_id, inverse_of: :approved_dataset, dependent: :nullify

  accepts_nested_attributes_for :datafiles, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :creators, reject_if: :invalid_name, allow_destroy: true
  accepts_nested_attributes_for :contributors, reject_if: :invalid_name, allow_destroy: true
  accepts_nested_attributes_for :funders,
                                reject_if: proc { |attributes| attributes["name"].blank? },
                                allow_destroy: true
  accepts_nested_attributes_for :related_materials, reject_if: :invalid_material, allow_destroy: true

  enum :publication_state, { draft: 0, published: 1 }, default: :draft

  scope :publicly_readable_now, lambda {
    published.where(
      <<~SQL.squish,
        COALESCE(NULLIF(embargo, ''), :none) <> :metadata
        OR (
          COALESCE(NULLIF(embargo, ''), :none) = :metadata
          AND release_date IS NOT NULL
          AND release_date <= :today
        )
      SQL
      none: EMBARGO_NONE,
      metadata: EMBARGO_METADATA,
      today: Date.current
    )
  }

  validates :key,             presence: true, uniqueness: true
  validates :title,           presence: true, unless: :draft?
  validates :owner_uid,       presence: true
  validates :depositor_name,  presence: true
  validates :depositor_email, presence: true
  validates :embargo, inclusion: { in: EMBARGO_OPTIONS }, allow_blank: true

  validate :release_date_required_for_embargo

  before_validation :set_key, on: :create
  before_validation :normalize_embargo
  before_save :set_primary_contact

  def to_param
    key
  end

  def generate_doi
    "10.5555/#{key}"
  end

  def persistent_url
    return if identifier.blank?

    "https://doi.org/#{identifier}"
  end

  def version_successor
    next_version_dataset
  end

  def next_version_dataset(include_unpublished: false)
    successor = nil

    if persistent_url.present?
      successor = RelatedMaterial.includes(:dataset).find_by(
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
        uri: persistent_url
      )&.dataset
    end

    if successor.nil?
      next_material_uri = related_materials.find_by(relation_type: RelatedMaterial::VERSION_NEW_RELATION)&.uri
      successor = resolve_related_dataset_from_uri(next_material_uri)
    end

    return nil if successor.nil?
    return successor if include_unpublished || successor.published?

    nil
  end

  def next_version_dataset_any
    next_version_dataset(include_unpublished: true)
  end

  def has_newer_published_version?
    version_successor.present?
  end

  def version_eligible?
    published? && !has_newer_published_version?
  end

  def nonversion_related_materials
    related_materials.reject(&:version_relation?)
  end

  def version_related_materials
    related_materials.select(&:version_relation?)
  end

  def previous_version_material
    related_materials.find_by(relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION)
  end

  def previous_version_dataset
    resolve_related_dataset_from_uri(previous_version_material&.uri)
  end

  def individual_creators
    creators.select { |creator| creator.type_of != CREATOR_TYPE_INSTITUTION }
  end

  def institutional_creators
    creators.select { |creator| creator.type_of == CREATOR_TYPE_INSTITUTION }
  end

  def prune_creators_for_mode!(org_mode:)
    if org_mode
      creators.where(type_of: [ nil, CREATOR_TYPE_PERSON ]).destroy_all
      creators.where(type_of: CREATOR_TYPE_INSTITUTION).update_all(type_of: CREATOR_TYPE_INSTITUTION)
    else
      creators.where(type_of: CREATOR_TYPE_INSTITUTION).destroy_all
      creators.where(type_of: [ nil, CREATOR_TYPE_PERSON ]).update_all(type_of: CREATOR_TYPE_PERSON)
    end
  end

  def missing_publish_fields
    missing = []
    missing << "title"            if title.blank?
    missing << "description"      if description.blank?
    missing << "creators"         if creators.empty?
    missing << "contact creator"  if creators.none?(&:contact_selected?)
    missing << "email address for all creators" if creators.any? { |creator| creator.email.blank? }
    missing << "release date when embargo is file or metadata" if (file_embargoed? || metadata_embargoed?) && release_date.blank?
    missing << "relation type for each related material URI" if related_materials.any? { |material| material.uri.present? && material.relation_type.blank? }
    missing << "depositor contact" if depositor_email.blank?
    missing
  end

  def ready_to_publish?
    missing_publish_fields.empty?
  end

  def embargo_mode
    embargo.presence || EMBARGO_NONE
  end

  def file_embargoed?
    embargo_mode == EMBARGO_FILE
  end

  def metadata_embargoed?
    embargo_mode == EMBARGO_METADATA
  end

  def embargo_released?(on_date: Date.current)
    release_date.present? && release_date <= on_date
  end

  def publicly_readable_now?(on_date: Date.current)
    return false unless published?
    return true unless metadata_embargoed?

    embargo_released?(on_date: on_date)
  end

  def files_publicly_readable_now?(on_date: Date.current)
    return false unless published?
    return true unless file_embargoed? || metadata_embargoed?

    embargo_released?(on_date: on_date)
  end

  def current_token
    scoped_tokens = Token.where(dataset_key: key)
    return nil if scoped_tokens.count.zero?
    return scoped_tokens.first if scoped_tokens.count == 1

    scoped_tokens.destroy_all
    new_token
  end

  def new_token
    Token.where(dataset_key: key).destroy_all
    Token.create!(dataset_key: key, identifier: Token.generate_auth_token)
  end

  private

  def normalize_embargo
    self.embargo = embargo_mode
  end

  def release_date_required_for_embargo
    return unless file_embargoed? || metadata_embargoed?
    return if release_date.present?

    errors.add(:release_date, "is required when embargo is file or metadata")
  end

  def invalid_name(attributes)
    attributes["family_name"].blank? &&
      attributes["given_name"].blank? &&
      attributes["institution_name"].blank? &&
      attributes["name"].blank?
  end

  def invalid_material(attributes)
    attributes["link"].blank? && attributes["citation"].blank?
  end

  def set_primary_contact
    self.corresponding_creator_name = nil
    self.corresponding_creator_email = nil

    creators.each do |creator|
      next unless creator.contact_selected?

      self.corresponding_creator_name = creator.display_name
      self.corresponding_creator_email = creator.email
      break
    end
  end

  def resolve_related_dataset_from_uri(uri)
    value = uri.to_s.strip
    return if value.blank?

    identifier = extract_identifier(value)
    return Dataset.find_by(identifier: identifier) if identifier.present?

    key = extract_dataset_key(value)
    return Dataset.find_by(key: key) if key.present?

    nil
  end

  def extract_identifier(value)
    return value if value.match?(/\A10\./)

    doi_prefixed = value.match(/\Adoi:(.+)\z/i)
    return doi_prefixed[1].strip if doi_prefixed

    doi_url = value.match(%r{\Ahttps?://doi\.org/(.+)\z}i)
    return doi_url[1].strip if doi_url

    nil
  end

  def extract_dataset_key(value)
    path = begin
      URI.parse(value).path
    rescue URI::InvalidURIError
      value
    end

    match = path.to_s.match(%r{/datasets/([^/?#]+)\z})
    match&.captures&.first
  end

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
