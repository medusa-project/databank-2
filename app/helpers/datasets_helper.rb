module DatasetsHelper
  FACET_SECTIONS = [
    { key: :subjects, title: "Subject Area", param_name: "subjects[]" },
    { key: :funders, title: "Funder", param_name: "funders[]" },
    { key: :publication_years, title: "Publication Year", param_name: "publication_years[]" },
    { key: :licenses, title: "License", param_name: "licenses[]" },
    { key: :publication_states, title: "Publication State", param_name: "publication_states[]" },
    { key: :depositors, title: "Depositor", param_name: "depositors[]" },
    { key: :external_files, title: "External Files", param_name: "external_files[]" }
  ].freeze

  def dataset_results_count_text(search:, datasets:, total_count:)
    start_item = search.offset_value + 1
    end_item = [ search.offset_value + datasets.length, total_count ].min

    "Displaying #{start_item} - #{end_item} of #{total_count} in total"
  end

  def dataset_index_facets
    FACET_SECTIONS
  end

  def dataset_facet_value(facet_key:, row:)
    value = row[:value]
    return value.to_s if [ :publication_years, :publication_states ].include?(facet_key)

    value
  end

  def dataset_facet_label(facet_key:, row:)
    case facet_key
    when :funders
      row.fetch(:label, row[:value])
    when :publication_states
      row[:value].to_s.humanize
    when :depositors, :external_files
      row[:label]
    else
      row[:value]
    end
  end

  def dataset_facet_checked?(facet_key:, value:)
    Array(params[facet_key]).include?(value)
  end

  def dataset_facet_id(facet_key:, value:)
    case facet_key
    when :subjects
      "subject_#{value.to_s.parameterize}"
    when :funders
      "funder_#{value.to_s.parameterize}"
    when :publication_years
      "publication_year_#{value}"
    when :licenses
      "license_#{value.to_s.parameterize}"
    when :publication_states
      "publication_state_#{value.to_s.parameterize}"
    when :depositors
      "depositor_#{value.to_s.parameterize}"
    when :external_files
      "external_files_#{value.to_s.parameterize}"
    end
  end

  def dataset_description_preview(description:, max_length: 240)
    return if description.blank? || description.length <= max_length

    {
      preview: description[0, max_length].rstrip,
      remainder: description[max_length..]
    }
  end

  def dataset_creator_list(dataset:)
    dataset.creators.map(&:name).reject(&:blank?).join("; ")
  end

  def dataset_publication_year(dataset:)
    (dataset.published_at || dataset.updated_at || dataset.created_at)&.year
  end

  def dataset_has_external_files?(dataset:)
    dataset.external_files_note.to_s.strip.present? || dataset.external_files_link.to_s.strip.present?
  end

  def dataset_hold_state(dataset:)
    dataset.hold_state.to_s
  end

  def dataset_suppressed_by_curator?(dataset:)
    hold_state = dataset_hold_state(dataset: dataset)
    return false if hold_state.blank?
    return false if hold_state == "none"
    return false if hold_state == "version"

    true
  end
end
