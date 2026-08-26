module DatasetsHelper
  def dataset_results_count_text(search:, datasets:, total_count:)
    start_item = search.offset_value + 1
    end_item = [ search.offset_value + datasets.length, total_count ].min

    "Displaying #{start_item} - #{end_item} of #{total_count} in total"
  end

  def dataset_index_facets
    role = current_user&.role.to_s
    Dataset.facets_for_role(role)
  end

  def dataset_facet_value(facet_key:, row:)
    value = row[:value]
    return value.to_s if [ :publication_years, :visibility_states ].include?(facet_key)

    value
  end

  def dataset_facet_label(facet_key:, row:)
    case facet_key
    when :funders
      row.fetch(:label, row[:value])
    when :visibility_states
      row.fetch(:label, row[:value])
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
    when :visibility_states
      "visibility_state_#{value.to_s.parameterize}"
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
    dataset.creator_list
  end

  def dataset_publication_year(dataset:)
    dataset.publication_year
  end

  def dataset_has_external_files?(dataset:)
    dataset.has_external_files?
  end

  def dataset_hold_state(dataset:)
    dataset.hold_state.to_s
  end

  def dataset_suppressed_by_curator?(dataset:)
    dataset.suppressed_by_curator?
  end
end
