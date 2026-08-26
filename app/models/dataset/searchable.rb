# frozen_string_literal: true

module Dataset::Searchable
  extend ActiveSupport::Concern

  class_methods do
    def facets_for_role(role)
      base_facets = [
        { key: :subjects, title: "Subject Area", param_name: "subjects[]" },
        { key: :funders, title: "Funder", param_name: "funders[]" },
        { key: :publication_years, title: "Publication Year", param_name: "publication_years[]" },
        { key: :licenses, title: "License", param_name: "licenses[]" }
      ]

      return base_facets unless %w[admin curator].include?(role.to_s)

      [
        { key: :depositors, title: "Depositor", param_name: "depositors[]" },
        *base_facets,
        { key: :visibility_states, title: "Visibility", param_name: "visibility_states[]" },
        { key: :external_files, title: "External Files", param_name: "external_files[]" }
      ]
    end
  end

  def has_external_files?
    external_files_note.to_s.strip.present? || external_files_link.to_s.strip.present?
  end

  def suppressed_by_curator?
    return false if hold_state.blank?
    return false if hold_state == "none"
    return false if hold_state == "version"

    true
  end
end
