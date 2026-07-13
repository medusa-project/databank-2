# frozen_string_literal: true

namespace :metrics do
  desc "Generate all metrics outputs"
  task generate_docs: :environment do
    Metric.refresh_all
  end

  desc "Generate metric files if they do not exist or are more than a day old"
  task ensure_fresh_metrics: :environment do
    Metric.ensure_fresh_metrics
  end

  desc "Generate datasets report files"
  task generate_dataset_reports: :environment do
    Metric.generate_datasets_reports
  end
end
