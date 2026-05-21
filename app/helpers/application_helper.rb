module ApplicationHelper
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
end
