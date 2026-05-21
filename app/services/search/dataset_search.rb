module Search
  class DatasetSearch
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100
    PER_PAGE_OPTIONS = [ 25, 50, 100 ].freeze
    OTHER_FUNDER_VALUE = "__other__".freeze
    TOP_FUNDER_NAMES = FunderCatalog.known_names.freeze

    AVAILABLE_FACETS = {
      "guest" => %i[subjects licenses funders publication_years],
      "depositor" => %i[subjects licenses funders publication_years publication_states],
      "admin" => %i[subjects licenses funders publication_years publication_states depositors]
    }.freeze

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
      relation.order(created_at: :desc)
    end

    def relation_with_query(relation)
      return relation if @query.blank?

      q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      relation.where(
        "title ILIKE :q OR description ILIKE :q OR keywords ILIKE :q OR subject ILIKE :q",
        q: q
      )
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
      funder_relation = relation.left_joins(:funders)

      if include_other && selected_funders.any?
        top_scope = funder_relation.where(funders: { name: selected_funders })
        other_scope = funder_relation
          .where.not(funders: { name: [ nil, "" ] })
          .where.not(funders: { name: TOP_FUNDER_NAMES })

        top_scope.or(other_scope).distinct
      elsif include_other
        funder_relation
          .where.not(funders: { name: [ nil, "" ] })
          .where.not(funders: { name: TOP_FUNDER_NAMES })
          .distinct
      else
        funder_relation.where(funders: { name: selected_funders }).distinct
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
      counts_by_name = relation
        .left_joins(:funders)
        .where.not(funders: { name: [ nil, "" ] })
        .group("funders.name")
        .order(Arel.sql("COUNT(DISTINCT datasets.id) DESC"), Arel.sql("funders.name"))
        .count("DISTINCT datasets.id")

      top_options = TOP_FUNDER_NAMES.filter_map do |name|
        count = counts_by_name[name]
        next if count.blank?

        { value: name, label: name, count: count }
      end

      other_names = counts_by_name.keys - TOP_FUNDER_NAMES
      return top_options if other_names.empty?

      other_count = relation
        .left_joins(:funders)
        .where(funders: { name: other_names })
        .distinct
        .count

      [ { value: OTHER_FUNDER_VALUE, label: "Other", count: other_count } ] + top_options
    end

    def publication_state_options(relation)
      relation
        .group(:publication_state)
        .order(:publication_state)
        .count
        .map do |value, count|
          key = Dataset.publication_states.key(value.to_i) || value.to_s
          { value: key, count: count }
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

    def normalize_filters(filters)
      raw = filters || {}
      {
        subjects: normalize_values(raw[:subjects] || raw["subjects"]),
        licenses: normalize_values(raw[:licenses] || raw["licenses"]),
        funders: normalize_values(raw[:funders] || raw["funders"]),
        publication_years: normalize_int_values(raw[:publication_years] || raw["publication_years"]),
        publication_states: normalize_values(raw[:publication_states] || raw["publication_states"]),
        depositors: normalize_values(raw[:depositors] || raw["depositors"])
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
