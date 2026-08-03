require "rails_helper"

RSpec.describe Metrics::DownloadMetricsAvailability do
  let(:metric_model) do
    class_double(Metric, current_calendar_year: 2026, current_fiscal_year: 26)
  end

  before do
    allow(metric_model).to receive(:year_metric_available?) do |metric_type:, year:, slice_type:|
      [
        [:dataset_downloads, 2026, :calendar],
        [:dataset_downloads, 2024, :calendar],
        [:dataset_downloads, 25, :fiscal],
        [:datafile_downloads, 26, :fiscal],
        [:datafile_downloads, 2023, :calendar]
      ].include?([metric_type, year, slice_type])
    end
  end

  it "builds availability per metric type" do
    availability = described_class.new(
      metric_model: metric_model,
      first_calendar_year: 2023,
      first_fiscal_year: 24
    )

    dataset = availability.for(:dataset_downloads)
    datafile = availability.for(:datafile_downloads)

    expect(availability.current_calendar_year).to eq(2026)
    expect(availability.current_fiscal_year).to eq(26)

    expect(dataset.current_available?(:calendar)).to be(true)
    expect(dataset.current_available?(:fiscal)).to be(false)
    expect(dataset.prior_calendar_years).to eq([2024])
    expect(dataset.prior_fiscal_years).to eq([25])

    expect(datafile.current_available?(:calendar)).to be(false)
    expect(datafile.current_available?(:fiscal)).to be(true)
    expect(datafile.prior_calendar_years).to eq([2023])
    expect(datafile.prior_fiscal_years).to eq([])
  end

  it "raises for unknown metric type" do
    availability = described_class.new(metric_model: metric_model)

    expect { availability.for(:unknown_metric) }.to raise_error(KeyError)
  end
end
