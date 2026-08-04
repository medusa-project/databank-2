module Search
  class DatasetSearch
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100
    PER_PAGE_OPTIONS = [ 25, 50, 100 ].freeze
    OTHER_FUNDER_VALUE = "__other__".freeze
    TOP_FUNDER_CODES = FunderCatalog.known_codes.freeze
    FUNDER_CODE_TO_NAME_MAP = FunderCatalog.code_to_name_map.freeze
    FUNDER_NAME_TO_CODE_MAP = FunderCatalog.name_to_code_map.freeze

    AVAILABLE_FACETS = {
      "guest" => %i[subjects licenses funders publication_years],
      "depositor" => %i[subjects licenses funders publication_years publication_states],
      "admin" => %i[subjects licenses funders publication_years publication_states depositors external_files]
    }.freeze

    EXTERNAL_FILES_HAS_VALUE = "has_external_files".freeze
    EXTERNAL_FILES_NONE_VALUE = "no_external_files".freeze

    attr_reader :page, :per_page

    def initialize(scope:, query:, filters:, page:, per_page:, role:)
      @scope = scope
      @query = query.to_s.strip
      @role = role.to_s
      @filters = normalize_filters(filters)
      @page = normalize_page(page)
      @per_page = normalize_per_page(per_page)
    end

    def results
      @results ||= begin
        relation = filtered_results_relation
        relation.offset(offset_value).limit(@per_page)
      end
    end

    def total_count
      @total_count ||= filtered_results_relation.except(:limit, :offset, :order).count
    end

    def total_pages
      return 0 if total_count.zero?

      (total_count.to_f / @per_page).ceil
    end

    def report_results
      @report_results ||= filtered_results_relation
    end

    def offset_value
      (@page - 1) * @per_page
    end

    def available_facets
      AVAILABLE_FACETS.fetch(@role, AVAILABLE_FACETS["guest"])
    end

    def facet_options
      @facet_options ||= begin
        relation = relation_with_query(@scope)

        options = {
          subjects: subject_options(relation),
          licenses: license_options(relation),
          publication_years: publication_year_options(relation),
          funders: funder_options(relation)
        }

        if available_facets.include?(:publication_states)
          options[:publication_states] = publication_state_options(relation)
        end

        if available_facets.include?(:depositors)
          options[:depositors] = depositor_options(relation)
        end

        if available_facets.include?(:external_files)
          options[:external_files] = external_files_options(relation)
        end

        options
      end
    end

    private

    def filtered_results_relation
      relation = relation_with_query(@scope)
      relation = filter_by_subjects(relation)
      relation = filter_by_licenses(relation)
      relation = filter_by_publication_years(relation)
      relation = filter_by_funders(relation)
      relation = filter_by_publication_states(relation)
      relation = filter_by_depositors(relation)
      relation = filter_by_external_files(relation)
      relation.order(created_at: :desc)
    end

    def relation_with_query(relation)
      return relation if @query.blank?

      q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      relation
        .left_joins(:funders)
        .where(
          "datasets.title ILIKE :q OR datasets.description ILIKE :q OR datasets.keywords ILIKE :q OR datasets.subject ILIKE :q OR funders.name ILIKE :q",
          q: q
        )
        .distinct
    end

    def filter_by_subjects(relation)
      return relation if @filters[:subjects].empty?

      relation.where(subject: @filters[:subjects])
    end

    def filter_by_licenses(relation)
      return relation if @filters[:licenses].empty?

      relation.where(license: @filters[:licenses])
    end

    def filter_by_publication_years(relation)
      return relation if @filters[:publication_years].empty?

      relation.where("EXTRACT(YEAR FROM published_at)::int IN (?)", @filters[:publication_years])
    end

    def filter_by_funders(relation)
      return relation if @filters[:funders].empty?

      selected_funders = @filters[:funders].dup
      include_other = selected_funders.delete(OTHER_FUNDER_VALUE)
      selected_codes = normalize_selected_funder_codes(values: selected_funders)
      funder_relation = relation.left_joins(:funders)

      if include_other && selected_codes.any?
        top_scope = top_funder_scope(relation: funder_relation, selected_codes: selected_codes)
        top_scope.or(other_funder_scope(relation: funder_relation)).distinct
      elsif include_other
        other_funder_scope(relation: funder_relation).distinct
      else
        top_funder_scope(relation: funder_relation, selected_codes: selected_codes).distinct
      end
    end

    def filter_by_publication_states(relation)
      return relation if @filters[:publication_states].empty?
      return relation unless available_facets.include?(:publication_states)

      relation.where(publication_state: @filters[:publication_states])
    end

    def filter_by_depositors(relation)
      return relation if @filters[:depositors].empty?
      return relation unless available_facets.include?(:depositors)

      relation.where(depositor_email: @filters[:depositors])
    end

    def filter_by_external_files(relation)
      return relation if @filters[:external_files].empty?
      return relation unless available_facets.include?(:external_files)

      selected = @filters[:external_files]
      include_has = selected.include?(EXTERNAL_FILES_HAS_VALUE)
      include_none = selected.include?(EXTERNAL_FILES_NONE_VALUE)

      return relation if include_has && include_none

      if include_has
        relation.where(external_files_present_sql)
      elsif include_none
        relation.where(external_files_absent_sql)
      else
        relation
      end
    end

    def subject_options(relation)
      relation
        .where.not(subject: [ nil, "" ])
        .group(:subject)
        .order(Arel.sql("COUNT(*) DESC"), :subject)
        .count
        .map { |value, count| { value: value, count: count } }
    end

    def license_options(relation)
      relation
        .where.not(license: [ nil, "" ])
        .group(:license)
        .order(Arel.sql("COUNT(*) DESC"), :license)
        .count
        .map { |value, count| { value: value, count: count } }
    end

    def publication_year_options(relation)
      relation
        .where.not(published_at: nil)
        .group("EXTRACT(YEAR FROM published_at)::int")
        .order(Arel.sql("EXTRACT(YEAR FROM published_at)::int DESC"))
        .count
        .map { |value, count| { value: value.to_i, count: count } }
    end

    def funder_options(relation)
      funder_rows = relation
        .left_joins(:funders)
        .where.not(funders: { name: [ nil, "" ] })
        .select("datasets.id AS dataset_id", "funders.code AS funder_code", "funders.name AS funder_name")

      grouped_dataset_ids = Hash.new { |hash, key| hash[key] = {} }
      other_dataset_ids = {}

      funder_rows.each do |row|
        canonical_code = canonical_top_funder_code(code: row.funder_code, name: row.funder_name)

        if canonical_code.present?
          grouped_dataset_ids[canonical_code][row.dataset_id] = true
        else
          other_dataset_ids[row.dataset_id] = true
        end
      end

      top_options = TOP_FUNDER_CODES.filter_map do |code|
        count = grouped_dataset_ids[code].length
        next if count.zero?

        { value: code, label: FUNDER_CODE_TO_NAME_MAP.fetch(code, code), count: count }
      end

      return top_options if other_dataset_ids.empty?

      [ { value: OTHER_FUNDER_VALUE, label: "Other", count: other_dataset_ids.length } ] + top_options
    end

    def top_funder_scope(relation:, selected_codes:)
      codes = Array(selected_codes).map(&:to_s).reject(&:blank?).uniq
      return relation.none if codes.empty?

      mapped_names = FUNDER_NAME_TO_CODE_MAP.filter_map do |name, code|
        name if codes.include?(code)
      end

      by_code = relation.where(funders: { code: codes })
      return by_code if mapped_names.empty?

      by_name = relation.where(funders: { code: [ nil, "" ], name: mapped_names })
      by_code.or(by_name)
    end

    def other_funder_scope(relation:)
      top_names = FUNDER_NAME_TO_CODE_MAP.keys
      relation
        .where.not(funders: { name: [ nil, "" ] })
        .where(
          "NOT ((COALESCE(funders.code, '') IN (:top_codes)) OR ((COALESCE(funders.code, '') = '') AND funders.name IN (:top_names)))",
          top_codes: TOP_FUNDER_CODES,
          top_names: top_names
        )
    end

    def canonical_top_funder_code(code:, name:)
      normalized_code = code.to_s.strip
      return normalized_code if TOP_FUNDER_CODES.include?(normalized_code)

      FUNDER_NAME_TO_CODE_MAP[name.to_s.strip]
    end

    def normalize_selected_funder_codes(values:)
      Array(values).filter_map do |value|
        normalized_value = value.to_s.strip
        next if normalized_value.blank?

        if TOP_FUNDER_CODES.include?(normalized_value)
          normalized_value
        else
          FUNDER_NAME_TO_CODE_MAP[normalized_value]
        end
      end.uniq
    end

    def publication_state_options(relation)
      relation
        .group(:publication_state)
        .order(:publication_state)
        .count
        .map do |value, count|
          key = publication_state_key(value)
          { value: key, count: count }
        end
    end

    def publication_state_key(value)
      normalized = value.to_s.strip

      if Dataset.publication_states.key?(normalized)
        normalized
      else
        Dataset.publication_states.key(value.to_i) || normalized
      end
    end

    def depositor_options(relation)
      relation
        .where.not(depositor_email: [ nil, "" ])
        .group(:depositor_email, :depositor_name)
        .order(Arel.sql("COUNT(*) DESC"), :depositor_name)
        .count
        .map do |(email, name), count|
          label = name.present? ? "#{name} (#{email})" : email
          { value: email, label: label, count: count }
        end
    end

    def external_files_options(relation)
      has_count = relation.where(external_files_present_sql).distinct.count(:id)
      none_count = relation.where(external_files_absent_sql).distinct.count(:id)

      options = []
      options << { value: EXTERNAL_FILES_HAS_VALUE, label: "Has External Files", count: has_count } if has_count.positive?
      options << { value: EXTERNAL_FILES_NONE_VALUE, label: "No External Files", count: none_count } if none_count.positive?
      options
    end

    def external_files_present_sql
      "COALESCE(NULLIF(BTRIM(datasets.external_files_note), ''), NULLIF(BTRIM(datasets.external_files_link), '')) IS NOT NULL"
    end

    def external_files_absent_sql
      "COALESCE(NULLIF(BTRIM(datasets.external_files_note), ''), NULLIF(BTRIM(datasets.external_files_link), '')) IS NULL"
    end

    def normalize_filters(filters)
      raw = filters || {}
      {
        subjects: normalize_values(raw[:subjects] || raw["subjects"]),
        licenses: normalize_values(raw[:licenses] || raw["licenses"]),
        funders: normalize_values(raw[:funders] || raw["funders"]),
        publication_years: normalize_int_values(raw[:publication_years] || raw["publication_years"]),
        publication_states: normalize_values(raw[:publication_states] || raw["publication_states"]),
        depositors: normalize_values(raw[:depositors] || raw["depositors"]),
        external_files: normalize_values(raw[:external_files] || raw["external_files"])
      }
    end

    def normalize_values(values)
      Array(values).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    def normalize_int_values(values)
      normalize_values(values).filter_map do |value|
        parsed = value.to_i
        parsed.positive? ? parsed : nil
      end
    end

    def normalize_page(value)
      parsed = value.to_i
      parsed.positive? ? parsed : 1
    end

    def normalize_per_page(value)
      parsed = value.to_i
      parsed = DEFAULT_PER_PAGE if parsed <= 0
      [ parsed, MAX_PER_PAGE ].min
    end
  end
end
