module ApplicationHelper
  def external_https_link_to(label, url, **options)
    safe_url = safe_https_url(url)
    return if safe_url.blank?

    link_to(label, safe_url, **options)
  end

  def dataset_persistent_url(dataset)
    return if dataset.identifier.blank?

    "https://doi.org/#{dataset.identifier}"
  end

  def dataset_plain_text_citation(dataset)
    citation_parts = []
    creator_names = dataset.creators.map(&:name).reject(&:blank?)

    citation_parts << creator_names.join("; ") if creator_names.any?

    year = dataset.published_at&.year || dataset.updated_at&.year || dataset.created_at&.year
    citation_parts << "(#{year})" if year.present?
    citation_parts << "#{dataset.title}." if dataset.title.present?
    citation_parts << dataset.publisher if dataset.publisher.present?

    persistent_url = dataset_persistent_url(dataset)
    citation_parts << persistent_url if persistent_url.present?

    citation_parts.join(" ")
  end

  def dataset_primary_contact_name(dataset)
    dataset.creators.find(&:contact?)&.name
  end

  private

  def safe_https_url(url)
    uri = URI.parse(url.to_s)
    return if uri.scheme.blank? || !%w[http https].include?(uri.scheme.downcase) || uri.host.blank?

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
