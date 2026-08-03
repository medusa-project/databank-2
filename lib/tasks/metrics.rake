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

  desc "Generate all historical download metrics (calendar and fiscal years)"
  task generate_all_download_metrics: :environment do
    puts "Starting generation of all historical download metrics..."
    Metric.generate_all_historical_downloads
    puts "\nGeneration complete! All historical metrics are now in storage."
  end

  desc "Archive old (non-current) download metrics from public/ to storage"
  task archive_old_metrics: :environment do
    puts "Starting archival of old download metrics..."
    Metric.archive_prior_year_downloads_to_storage
    puts "Archival complete!"
  end

  desc "List archived download metrics in storage"
  task list_archived_metrics: :environment do
    puts "Archived download metrics in storage:"
    puts "Note: Listing all archived metrics requires StorageManager support for key listing"
    puts "Currently stored metrics can be retrieved via:"
    puts "  GET /metrics/archived/:metric_type/:year/:slice_type"
    puts ""
    puts "Example URLs:"
    puts "  /metrics/archived/dataset_downloads/2025/calendar"
    puts "  /metrics/archived/datafile_downloads/FY25/fiscal"
  end
end

desc "Generate all historical download metrics (calendar and fiscal years)"
task generate_all_download_metrics: "metrics:generate_all_download_metrics"

desc "Archive old (non-current) download metrics from public/ to storage"
task archive_old_metrics: "metrics:archive_old_metrics"

desc "List archived download metrics in storage"
task list_archived_metrics: "metrics:list_archived_metrics"
