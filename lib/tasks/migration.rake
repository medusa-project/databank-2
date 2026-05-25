namespace :migration do
  namespace :guides do
    desc "Import a legacy guides bundle (replace-all)"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_guides.ndjson")
      bundle_path = dir.join(bundle_file)

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

      summary = Migration::GuidesBundleImportService.new(
        bundle_path: bundle_path.to_s,
        dry_run: dry_run,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        replace_all: replace_all
      ).call

      puts "Bundle: #{bundle_path}"
      puts "Checksum: #{checksum_path || 'none'}"
      puts "Manifest: #{manifest_path || 'none'}"
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
      overwrite = ENV.fetch("OVERWRITE", "false").casecmp("true").zero?
      dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?

      summary = Migration::BundleImportService.new(
        bundle_path: bundle_path,
        overwrite: overwrite,
        dry_run: dry_run,
        checksum_path: checksum_path,
        manifest_path: manifest_path
      ).call

      puts "Bundle: #{summary[:bundle_path]}"
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
    end

    desc "Import copied legacy export artifacts from a directory"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_datasets.ndjson")
      bundle_path = dir.join(bundle_file)

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

      summary = Migration::BundleImportService.new(
        bundle_path: bundle_path.to_s,
        overwrite: overwrite,
        dry_run: dry_run,
        checksum_path: checksum_path,
        manifest_path: manifest_path
      ).call

      puts "Bundle: #{bundle_path}"
      puts "Checksum: #{checksum_path || 'none'}"
      puts "Manifest: #{manifest_path || 'none'}"
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
    end
  end
end
