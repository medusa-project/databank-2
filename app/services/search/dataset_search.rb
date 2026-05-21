module Search
  class DatasetSearch
    def initialize(scope:, query:, subject:)
      @scope = scope
      @query = query.to_s.strip
      @subject = subject.to_s.strip
    end

    def results
      database_results
    end

    private

    def filtered_scope_for_subject
      return @scope if @subject.blank?

      @scope.where("LOWER(subject) = ?", @subject.downcase)
    end

    def database_results
      relation = filtered_scope_for_subject

      if @query.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        relation = relation.where(
          "title ILIKE :q OR description ILIKE :q OR keywords ILIKE :q OR subject ILIKE :q",
          q: q
        )
      end

      relation.order(created_at: :desc)
    end
  end
end
