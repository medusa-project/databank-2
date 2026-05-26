def migration_report_path(dir, report_path)
  return dir.join("import_report.json") unless report_path.present?

  path = Pathname(report_path)
  path.absolute? ? path : dir.join(path)
end

def record_migration_run(run_type:, label: nil, bundle_path:, checksum_path: nil, manifest_path: nil, report_path: nil, details: {})
  recorder = Migration::RunRecorder.new(
    run_type: run_type,
    label: label,
    bundle_path: bundle_path,
    checksum_path: checksum_path,
    manifest_path: manifest_path,
    report_path: report_path,
    details: details
  )

  run = recorder.start!
  summary = yield
  recorder.finish!(run: run, summary: summary)
  summary
rescue StandardError => e
  summary ||= {
    bundle_path: bundle_path,
    created: 0,
    updated: 0,
    skipped_existing: 0,
    would_create: 0,
    would_update: 0,
    failed: 1,
    validation_error: e.message,
    records: []
  }

  if defined?(recorder) && run.present?
    begin
      recorder.finish!(run: run, summary: summary)
    rescue StandardError => finish_error
      warn "Migration run completion unavailable: #{finish_error.message}"
    end
  end

  raise
end

namespace :migration do
  namespace :spotlights do
    desc "Import a legacy researcher spotlight bundle"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_featured_researchers.ndjson")
      bundle_path = dir.join(bundle_file)
      report_path = ENV["REPORT_FILE"].presence
      resolved_report_path = migration_report_path(dir, report_path)

      checksum_path = if ENV.key?("CHECKSUM")
        ENV["CHECKSUM"]
      elsif ENV.key?("CHECKSUM_FILE")
        dir.join(ENV.fetch("CHECKSUM_FILE")).to_s
      else
        candidate = dir.join("#{bundle_file}.sha256")
        candidate.file? ? candidate.to_s : nil
      end

      manifest_path = if ENV.key?("MANIFEST")
        ENV["MANIFEST"]
      elsif ENV.key?("MANIFEST_FILE")
        dir.join(ENV.fetch("MANIFEST_FILE")).to_s
      else
        candidate = dir.join("manifest.json")
        candidate.file? ? candidate.to_s : nil
      end

      dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?
      replace_all = ENV.fetch("REPLACE_ALL", "true").casecmp("true").zero?
      overwrite = ENV.fetch("OVERWRITE", "false").casecmp("true").zero?

      summary = record_migration_run(
        run_type: "featured_researchers_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run,
          replace_all: replace_all,
          overwrite: overwrite
        }
      ) do
        Migration::FeaturedResearchersBundleImportService.new(
          bundle_path: bundle_path.to_s,
          dry_run: dry_run,
          checksum_path: checksum_path,
          manifest_path: manifest_path,
          replace_all: replace_all,
          overwrite: overwrite,
          report_path: resolved_report_path.to_s
        ).call
      end

      puts "Bundle: #{bundle_path}"
      puts "Checksum: #{checksum_path || 'none'}"
      puts "Manifest: #{manifest_path || 'none'}"
      puts "Report: #{resolved_report_path}"
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

  namespace :guides do
    desc "Import a legacy guides bundle (replace-all)"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_guides.ndjson")
      bundle_path = dir.join(bundle_file)
      report_path = ENV["REPORT_FILE"].presence
      resolved_report_path = migration_report_path(dir, report_path)

      checksum_path = if ENV.key?("CHECKSUM")
        ENV["CHECKSUM"]
      elsif ENV.key?("CHECKSUM_FILE")
        dir.join(ENV.fetch("CHECKSUM_FILE")).to_s
      else
        candidate = dir.join("#{bundle_file}.sha256")
        candidate.file? ? candidate.to_s : nil
      end

      manifest_path = if ENV.key?("MANIFEST")
        ENV["MANIFEST"]
      elsif ENV.key?("MANIFEST_FILE")
        dir.join(ENV.fetch("MANIFEST_FILE")).to_s
      else
        candidate = dir.join("manifest.json")
        candidate.file? ? candidate.to_s : nil
      end

      dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?
      replace_all = ENV.fetch("REPLACE_ALL", "true").casecmp("true").zero?

      summary = record_migration_run(
        run_type: "guides_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run,
          replace_all: replace_all
        }
      ) do
        Migration::GuidesBundleImportService.new(
          bundle_path: bundle_path.to_s,
          dry_run: dry_run,
          checksum_path: checksum_path,
          manifest_path: manifest_path,
          replace_all: replace_all,
          report_path: resolved_report_path.to_s
        ).call
      end

      puts "Bundle: #{bundle_path}"
      puts "Checksum: #{checksum_path || 'none'}"
      puts "Manifest: #{manifest_path || 'none'}"
      puts "Report: #{resolved_report_path}"
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

  namespace :sample do
    desc "Fetch public dataset JSON payloads listed in working/datasets.json"
    task fetch: :environment do
      list_path = ENV.fetch("LIST", Rails.root.join("working", "datasets.json").to_s)
      output_root = ENV.fetch("OUTPUT_ROOT", Rails.root.join("working", "migration_samples").to_s)
      limit = ENV["LIMIT"]

      summary = Migration::SampleFetchService.new(
        list_path: list_path,
        output_root: output_root,
        limit: limit&.to_i
      ).call

      puts "Run directory: #{summary[:run_dir]}"
      puts "Fetched: #{summary[:fetched]}, Failed: #{summary[:failed]}, Listed: #{summary[:total_listed]}"
    end

    desc "Import previously fetched sample payloads into databank-2"
    task import: :environment do
      input_dir = ENV.fetch("INPUT_DIR")
      overwrite = ENV.fetch("OVERWRITE", "false").casecmp("true").zero?
      dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?

      summary = Migration::SampleImportService.new(
        input_dir: input_dir,
        overwrite: overwrite,
        dry_run: dry_run
      ).call

      puts "Input directory: #{summary[:input_dir]}"
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
    end
  end

  namespace :bundle do
    desc "Import a secure NDJSON migration bundle exported from legacy databank"
    task import: :environment do
      bundle_path = ENV.fetch("BUNDLE")
      checksum_path = ENV["CHECKSUM"]
      manifest_path = ENV["MANIFEST"]
      report_path = ENV["REPORT_FILE"].presence
      resolved_report_path = migration_report_path(Pathname(bundle_path).dirname, report_path)
      overwrite = ENV.fetch("OVERWRITE", "false").casecmp("true").zero?
      dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?

      summary = record_migration_run(
        run_type: "bundle_import",
        bundle_path: bundle_path,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run,
          overwrite: overwrite
        }
      ) do
        Migration::BundleImportService.new(
          bundle_path: bundle_path,
          overwrite: overwrite,
          dry_run: dry_run,
          checksum_path: checksum_path,
          manifest_path: manifest_path,
          report_path: resolved_report_path.to_s
        ).call
      end

      puts "Bundle: #{summary[:bundle_path]}"
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      puts "Report: #{resolved_report_path}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
    end

    desc "Import copied legacy export artifacts from a directory"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_datasets.ndjson")
      bundle_path = dir.join(bundle_file)
      report_path = ENV["REPORT_FILE"].presence
      resolved_report_path = migration_report_path(dir, report_path)

      checksum_path = if ENV.key?("CHECKSUM")
        ENV["CHECKSUM"]
      elsif ENV.key?("CHECKSUM_FILE")
        dir.join(ENV.fetch("CHECKSUM_FILE")).to_s
      else
        candidate = dir.join("#{bundle_file}.sha256")
        candidate.file? ? candidate.to_s : nil
      end

      manifest_path = if ENV.key?("MANIFEST")
        ENV["MANIFEST"]
      elsif ENV.key?("MANIFEST_FILE")
        dir.join(ENV.fetch("MANIFEST_FILE")).to_s
      else
        candidate = dir.join("manifest.json")
        candidate.file? ? candidate.to_s : nil
      end

      overwrite = ENV.fetch("OVERWRITE", "false").casecmp("true").zero?
      dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?

      summary = record_migration_run(
        run_type: "bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run,
          overwrite: overwrite
        }
      ) do
        Migration::BundleImportService.new(
          bundle_path: bundle_path.to_s,
          overwrite: overwrite,
          dry_run: dry_run,
          checksum_path: checksum_path,
          manifest_path: manifest_path,
          report_path: resolved_report_path.to_s
        ).call
      end

      puts "Bundle: #{bundle_path}"
      puts "Checksum: #{checksum_path || 'none'}"
      puts "Manifest: #{manifest_path || 'none'}"
      puts "Report: #{resolved_report_path}"
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
    end
  end
end
