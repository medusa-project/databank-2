class MetricRefreshJob < ApplicationJob
  queue_as :default

  METRIC_KEY_TO_METHOD = {
    dataset_downloads_json: :write_dataset_downloads_json,
    datafile_downloads_json: :write_datafile_downloads_json,
    datasets_tsv: :write_datasets_tsv,
    datafiles_csv: :write_datafiles_csv,
    container_contents_csv: :write_container_contents_csv,
    funders_csv: :write_funders_csv,
    related_materials_csv: :write_related_materials_csv
  }.freeze

  def perform(metric_key)
    normalized_key = metric_key.to_sym
    method_name = METRIC_KEY_TO_METHOD[normalized_key]
    raise ArgumentError, "Unknown metric key: #{normalized_key}" unless method_name

    Metric.public_send(method_name)
  end
end
