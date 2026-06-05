require "digest"

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
  namespace :permissions do
    desc "Import legacy curator/deposit-exception permissions bundle into typed records"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_permissions.ndjson")
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

      summary = record_migration_run(
        run_type: "permissions_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run
        }
      ) do
        raise ArgumentError, "bundle not found: #{bundle_path}" unless bundle_path.file?

        if checksum_path.present? && !File.file?(checksum_path)
          raise ArgumentError, "checksum file not found: #{checksum_path}"
        end

        if manifest_path.present? && !File.file?(manifest_path)
          raise ArgumentError, "manifest file not found: #{manifest_path}"
        end

        manifest_data = manifest_path.present? ? JSON.parse(File.read(manifest_path)) : nil
        expected_checksum = manifest_data&.dig("sha256").to_s.strip.presence
        if expected_checksum.blank? && checksum_path.present?
          expected_checksum = File.read(checksum_path).strip.split.first.to_s.strip.presence
        end

        if expected_checksum.present?
          actual_checksum = Digest::SHA256.file(bundle_path).hexdigest
          unless actual_checksum == expected_checksum
            raise ArgumentError, "bundle checksum mismatch"
          end
        end

        summary = {
          bundle_path: bundle_path.to_s,
          created: 0,
          updated: 0,
          skipped_existing: 0,
          would_create: 0,
          would_update: 0,
          failed: 0,
          validation_error: nil,
          records: []
        }

        line_count = 0
        type_counts = Hash.new(0)

        File.foreach(bundle_path).with_index(1) do |line, line_number|
          next if line.strip.empty?

          payload = JSON.parse(line)
          type = payload["type"].to_s
          attributes = payload["attributes"] || {}
          email = attributes["email"].to_s.strip.downcase

          if email.blank? || !(email =~ URI::MailTo::EMAIL_REGEXP)
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, message: "invalid email" }
            next
          end

          model_class = case type
          when "ManagedCurator"
            ManagedCurator
          when "ManagedDepositException"
            ManagedDepositException
          else
            nil
          end

          if model_class.nil?
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, email: email, message: "unsupported type" }
            next
          end

          type_counts[type] += 1
          line_count += 1

          if dry_run
            status = model_class.exists?(email: email) ? :skipped_existing : :would_create
            summary[status == :would_create ? :would_create : :skipped_existing] += 1
            summary[:records] << { line: line_number, status: status, type: type, email: email }
            next
          end

          record = model_class.find_or_initialize_by(email: email)
          if record.persisted?
            summary[:skipped_existing] += 1
            summary[:records] << { line: line_number, status: :skipped_existing, type: type, email: email }
          elsif record.save
            summary[:created] += 1
            summary[:records] << { line: line_number, status: :created, type: type, email: email }
          else
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, email: email, message: record.errors.full_messages.to_sentence }
          end
        rescue JSON::ParserError => e
          summary[:failed] += 1
          summary[:records] << { line: line_number, status: :failed, message: "invalid JSON: #{e.message}" }
        end

        if manifest_data&.dig("record_count").present?
          expected_count = manifest_data["record_count"].to_i
          if expected_count != line_count
            raise ArgumentError, "bundle record count mismatch"
          end
        end

        if manifest_data&.dig("counts").is_a?(Hash)
          manifest_data["counts"].each do |record_type, expected|
            next unless [ "ManagedCurator", "ManagedDepositException" ].include?(record_type)

            if type_counts[record_type].to_i != expected.to_i
              raise ArgumentError, "manifest count mismatch for #{record_type}"
            end
          end
        end

        summary[:processed_count] = line_count
        summary[:expected_record_count] = manifest_data&.dig("record_count")
        summary[:checksum] = expected_checksum
        summary[:counts] = {
          "ManagedCurator" => type_counts["ManagedCurator"].to_i,
          "ManagedDepositException" => type_counts["ManagedDepositException"].to_i
        }

        Migration::RunReportWriter.new(
          report_path: resolved_report_path,
          report: {
            generated_at: Time.current.utc.iso8601,
            import_type: "permissions_bundle",
            bundle_path: bundle_path.to_s,
            checksum_path: checksum_path,
            manifest_path: manifest_path,
            summary: summary
          }
        ).call

        summary
      end

      puts "Bundle: #{bundle_path}"
      puts "Checksum: #{checksum_path || 'none'}"
      puts "Manifest: #{manifest_path || 'none'}"
      puts "Report: #{resolved_report_path}"
      puts "Created: #{summary[:created]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}"
      end
      if summary[:counts].is_a?(Hash)
        puts "ManagedCurator records processed: #{summary[:counts].fetch('ManagedCurator', 0)}"
        puts "ManagedDepositException records processed: #{summary[:counts].fetch('ManagedDepositException', 0)}"
      end
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

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
