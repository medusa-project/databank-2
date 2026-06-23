require "rails_helper"

RSpec.describe MetricRefreshJob, type: :job do
  it "dispatches to the metric writer for a known key" do
    allow(Metric).to receive(:write_dataset_downloads_json)

    described_class.perform_now(:dataset_downloads_json)

    expect(Metric).to have_received(:write_dataset_downloads_json)
  end

  it "raises for an unknown metric key" do
    expect do
      described_class.perform_now(:unknown_metric)
    end.to raise_error(ArgumentError, "Unknown metric key: unknown_metric")
  end
end
