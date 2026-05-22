class Dataset < ApplicationRecord
  KEY_PREFIX = ENV.fetch("DATASET_KEY_PREFIX", "IDB").freeze
  KEY_DIGITS = 7
  CREATOR_TYPE_PERSON = 0
  CREATOR_TYPE_INSTITUTION = 1

  has_many :datafiles,         dependent: :destroy
  has_many :creators,          -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :contributors,      -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :funders,           -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
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

  validates :key,             presence: true, uniqueness: true
  validates :title,           presence: true, unless: :draft?
  validates :owner_uid,       presence: true
  validates :depositor_name,  presence: true
  validates :depositor_email, presence: true

  before_validation :set_key, on: :create
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

  def convert_creators_for_org_mode!
    if org_creators?
      ind_creators_to_contributors!
    else
      contributors_to_ind_creators!
    end
  end

  def missing_publish_fields
    missing = []
    missing << "title"            if title.blank?
    missing << "description"      if description.blank?
    missing << "creators"         if creators.empty?
    missing << "contact creator"  if creators.none?(&:contact_selected?)
    missing << "email address for all creators" if creators.any? { |creator| creator.email.blank? }
    missing << "relation type for each related material URI" if related_materials.any? { |material| material.uri.present? && material.relation_type.blank? }
    missing << "depositor contact" if depositor_email.blank?
    missing
  end

  def ready_to_publish?
    missing_publish_fields.empty?
  end

  private

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

  def ind_creators_to_contributors!
    transaction do
      individual_creators.each do |creator|
        Contributor.create!(
          dataset_id: id,
          name: creator.name,
          family_name: creator.family_name,
          given_name: creator.given_name,
          institution_name: creator.institution_name,
          email: creator.email,
          identifier: creator.identifier,
          identifier_scheme: creator.identifier_scheme,
          type_of: CREATOR_TYPE_PERSON,
          row_position: creator.row_position,
          position: creator.position,
          row_order: creator.row_order,
          is_contact: creator.contact_selected?
        )
        creator.destroy!
      end
    end
  end

  def contributors_to_ind_creators!
    transaction do
      contributors.each do |contributor|
        Creator.create!(
          dataset_id: id,
          name: contributor.name,
          family_name: contributor.family_name,
          given_name: contributor.given_name,
          institution_name: contributor.institution_name,
          email: contributor.email,
          identifier: contributor.identifier,
          identifier_scheme: contributor.identifier_scheme,
          type_of: CREATOR_TYPE_PERSON,
          row_position: contributor.row_position,
          position: contributor.position,
          row_order: contributor.row_order,
          is_contact: contributor.is_contact,
          contact: contributor.is_contact
        )
        contributor.destroy!
      end
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
