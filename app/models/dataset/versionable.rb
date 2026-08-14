module Dataset::Versionable
  extend ActiveSupport::Concern

  included do
    has_many :version_requests, dependent: :destroy
    has_many :approved_version_requests, class_name: "VersionRequest", foreign_key: :approved_dataset_id, inverse_of: :approved_dataset, dependent: :nullify
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
      next_material_uri = related_materials.detect { |material| material.relation_types.include?(RelatedMaterial::VERSION_NEW_RELATION) }&.uri
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
    related_materials.detect { |material| material.relation_types.include?(RelatedMaterial::VERSION_PREVIOUS_RELATION) }
  end

  def previous_version_dataset
    resolve_related_dataset_from_uri(previous_version_material&.uri)
  end

  def version_request_pending?
    if association(:version_requests).loaded?
      version_requests.any?(&:pending?)
    else
      version_requests.pending.exists?
    end
  end

  def version_request_approved?
    if association(:version_requests).loaded?
      version_requests.any?(&:approved?)
    else
      version_requests.approved.exists?
    end
  end

  private

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
end
