# frozen_string_literal: true

namespace :metrics do
  desc "Generate all metrics outputs"
  task generate_docs: :environment do
    Metric.refresh_all
  end

  desc "Generate datasets report files"
  task generate_dataset_reports: :environment do
    Metric.generate_datasets_reports
  end
end
