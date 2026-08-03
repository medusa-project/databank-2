# frozen_string_literal: true

module Metrics
  class DownloadMetricsAvailability
    METRIC_TYPES = %i[dataset_downloads datafile_downloads].freeze

    Section = Struct.new(
      :metric_type,
      :current_calendar_available,
      :current_fiscal_available,
      :prior_calendar_years,
      :prior_fiscal_years,
      keyword_init: true
    ) do
      def current_available?(slice_type)
        case slice_type
        when :calendar
          current_calendar_available
        when :fiscal
          current_fiscal_available
        else
          raise ArgumentError, "Invalid slice_type: #{slice_type}"
        end
      end
    end

    attr_reader :current_calendar_year, :current_fiscal_year

    def initialize(
      metric_model: Metric,
      current_calendar_year: nil,
      current_fiscal_year: nil,
      first_calendar_year: Metric::FIRST_DOWNLOAD_CALENDAR_YEAR,
      first_fiscal_year: Metric::FIRST_DOWNLOAD_FISCAL_YEAR
    )
      @metric_model = metric_model
      @current_calendar_year = current_calendar_year || metric_model.current_calendar_year
      @current_fiscal_year = current_fiscal_year || metric_model.current_fiscal_year
      @first_calendar_year = first_calendar_year
      @first_fiscal_year = first_fiscal_year
      @sections = build_sections
    end

    def for(metric_type)
      @sections.fetch(metric_type.to_sym)
    end

    private

    attr_reader :metric_model, :first_calendar_year, :first_fiscal_year

    def build_sections
      METRIC_TYPES.each_with_object({}) do |metric_type, sections|
        sections[metric_type] = Section.new(
          metric_type: metric_type,
          current_calendar_available: metric_available?(metric_type: metric_type, year: current_calendar_year, slice_type: :calendar),
          current_fiscal_available: metric_available?(metric_type: metric_type, year: current_fiscal_year, slice_type: :fiscal),
          prior_calendar_years: available_prior_years(
            metric_type: metric_type,
            first_year: first_calendar_year,
            current_year: current_calendar_year,
            slice_type: :calendar
          ),
          prior_fiscal_years: available_prior_years(
            metric_type: metric_type,
            first_year: first_fiscal_year,
            current_year: current_fiscal_year,
            slice_type: :fiscal
          )
        )
      end
    end

    def available_prior_years(metric_type:, first_year:, current_year:, slice_type:)
      (first_year...current_year).to_a.reverse.select do |year|
        metric_available?(metric_type: metric_type, year: year, slice_type: slice_type)
      end
    end

    def metric_available?(metric_type:, year:, slice_type:)
      metric_model.year_metric_available?(metric_type: metric_type, year: year, slice_type: slice_type)
    end
  end
end