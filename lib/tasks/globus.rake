namespace :globus do
  desc "Import Datafile records for files in globus_ingest using <dataset_key>/<filename>"
  task import_datafiles_from_ingest: :environment do
    dataset_key = ENV["DATASET_KEY"].to_s.strip.presence
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", false))
    dataset_limit = ENV["DATASET_LIMIT"].to_i

    summary = Globus::IngestImportService.new(
      dataset_key: dataset_key,
      dry_run: dry_run,
      dataset_limit: dataset_limit
    ).call

    puts JSON.pretty_generate(summary.except(:records))
  end

  desc "Copy publicly-readable Datafiles to globus_download using <dataset_key>/<binary_name>"
  task copy_public_datafiles: :environment do
    dataset_key = ENV["DATASET_KEY"].to_s.strip.presence
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", false))
    dataset_limit = ENV["DATASET_LIMIT"].to_i

    summary = Globus::PublicCopyService.new(
      dataset_key: dataset_key,
      dry_run: dry_run,
      dataset_limit: dataset_limit
    ).call

    puts JSON.pretty_generate(summary.except(:records))
  end
end
