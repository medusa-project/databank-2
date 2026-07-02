require "digest"

def migration_report_path(dir, report_path)
  return dir.join("import_report.json") unless report_path.present?

  path = Pathname(report_path)
  path.absolute? ? path : dir.join(path)
end

def record_migration_run(run_type:, bundle_path:, label: nil, checksum_path: nil, manifest_path: nil, report_path: nil, details: {})
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
  namespace :users do
    desc "Import legacy users bundle into databank-2 users"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_users.ndjson")
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
        run_type: "users_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run
        }
      ) do
        Migration::UsersBundleImportService.new(
          bundle_path: bundle_path.to_s,
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
      puts "Skipped unsupported role: #{summary[:skipped_unsupported_role]}"
      puts "Skipped invalid identity: #{summary[:skipped_invalid_identity]}"
      puts "Reconciled by email: #{summary[:reconciled_by_email]}"
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

  namespace :dataset_access_grants do
    desc "Import legacy dataset access grants bundle into typed records"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_dataset_access_grants.ndjson")
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
        run_type: "dataset_access_grants_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run
        }
      ) do
        raise ArgumentError, "bundle not found: #{bundle_path}" unless bundle_path.file?
        raise ArgumentError, "checksum file not found: #{checksum_path}" if checksum_path.present? && !File.file?(checksum_path)
        raise ArgumentError, "manifest file not found: #{manifest_path}" if manifest_path.present? && !File.file?(manifest_path)

        manifest_data = manifest_path.present? ? JSON.parse(File.read(manifest_path)) : nil
        expected_checksum = manifest_data&.dig("sha256").to_s.strip.presence
        if expected_checksum.blank? && checksum_path.present?
          expected_checksum = File.read(checksum_path).strip.split.first.to_s.strip.presence
        end

        if expected_checksum.present?
          actual_checksum = Digest::SHA256.file(bundle_path).hexdigest
          raise ArgumentError, "bundle checksum mismatch" unless actual_checksum == expected_checksum
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

        total_line_count = 0
        grants_line_count = 0
        access_counts = Hash.new(0)

        File.foreach(bundle_path).with_index(1) do |line, line_number|
          next if line.strip.empty?

          total_line_count += 1

          payload = JSON.parse(line)
          type = payload["type"].to_s
          attributes = payload["attributes"] || {}
          dataset_key = attributes["dataset_key"].to_s.strip
          email = DatasetAccessGrant.normalize_email_value(attributes["email"])
          access_level = attributes["access_level"].to_s.strip

          if type != "DatasetAccessGrant"
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, message: "unsupported type" }
            next
          end

          grants_line_count += 1

          if dataset_key.blank?
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, message: "missing dataset_key" }
            next
          end

          if email.blank? || !(email =~ URI::MailTo::EMAIL_REGEXP)
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, dataset_key: dataset_key, message: "invalid email" }
            next
          end

          unless DatasetAccessGrant.access_levels.key?(access_level)
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, dataset_key: dataset_key, email: email, message: "invalid access level" }
            next
          end

          access_counts[access_level] += 1

          dataset = Dataset.find_by(key: dataset_key)
          if dataset.nil?
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, dataset_key: dataset_key, email: email, message: "dataset not found" }
            next
          end

          existing = dataset.dataset_access_grants.find_by(email: email)
          if dry_run
            status = if existing.nil?
              :would_create
            elsif existing.access_level == access_level
              :skipped_existing
            else
              :would_update
            end

            summary[status] += 1
            summary[:records] << { line: line_number, status: status, dataset_key: dataset_key, email: email, access_level: access_level }
            next
          end

          if existing.nil?
            record = dataset.dataset_access_grants.new(email: email, access_level: access_level)
            if record.save
              summary[:created] += 1
              summary[:records] << { line: line_number, status: :created, dataset_key: dataset_key, email: email, access_level: access_level }
            else
              summary[:failed] += 1
              summary[:records] << { line: line_number, status: :failed, dataset_key: dataset_key, email: email, access_level: access_level, message: record.errors.full_messages.to_sentence }
            end
          elsif existing.access_level == access_level
            summary[:skipped_existing] += 1
            summary[:records] << { line: line_number, status: :skipped_existing, dataset_key: dataset_key, email: email, access_level: access_level }
          elsif existing.update(access_level: access_level)
            summary[:updated] += 1
            summary[:records] << { line: line_number, status: :updated, dataset_key: dataset_key, email: email, access_level: access_level }
          else
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, dataset_key: dataset_key, email: email, access_level: access_level, message: existing.errors.full_messages.to_sentence }
          end
        rescue JSON::ParserError => e
          summary[:failed] += 1
          summary[:records] << { line: line_number, status: :failed, message: "invalid JSON: #{e.message}" }
        end

        if manifest_data&.dig("record_count").present?
          expected_count = manifest_data["record_count"].to_i
          raise ArgumentError, "bundle record count mismatch" if expected_count != total_line_count
        end

        if manifest_data&.dig("counts").is_a?(Hash)
          expected_total = manifest_data["counts"]["DatasetAccessGrant"]
          if expected_total.present? && expected_total.to_i != grants_line_count
            raise ArgumentError, "manifest count mismatch for DatasetAccessGrant"
          end

          %w[viewer editor].each do |level|
            expected = manifest_data["counts"][level]
            next if expected.nil?

            raise ArgumentError, "manifest count mismatch for #{level}" if access_counts[level].to_i != expected.to_i
          end
        end

        summary[:processed_count] = grants_line_count
        summary[:expected_record_count] = manifest_data&.dig("record_count")
        summary[:checksum] = expected_checksum
        summary[:counts] = {
          "DatasetAccessGrant" => grants_line_count,
          "viewer" => access_counts["viewer"].to_i,
          "editor" => access_counts["editor"].to_i
        }

        Migration::RunReportWriter.new(
          report_path: resolved_report_path,
          report: {
            generated_at: Time.current.utc.iso8601,
            import_type: "dataset_access_grants_bundle",
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
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
      if summary[:counts].is_a?(Hash)
        puts "DatasetAccessGrant records processed: #{summary[:counts].fetch('DatasetAccessGrant', 0)}"
        puts "Viewer grants processed: #{summary[:counts].fetch('viewer', 0)}"
        puts "Editor grants processed: #{summary[:counts].fetch('editor', 0)}"
      end
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

  namespace :medusa_ingests do
    desc "Import legacy Medusa ingest bundle into external delivery tracking"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_medusa_ingests.ndjson")
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
        run_type: "medusa_ingests_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run
        }
      ) do
        raise ArgumentError, "bundle not found: #{bundle_path}" unless bundle_path.file?
        raise ArgumentError, "checksum file not found: #{checksum_path}" if checksum_path.present? && !File.file?(checksum_path)
        raise ArgumentError, "manifest file not found: #{manifest_path}" if manifest_path.present? && !File.file?(manifest_path)

        manifest_data = manifest_path.present? ? JSON.parse(File.read(manifest_path)) : nil
        expected_checksum = manifest_data&.dig("sha256").to_s.strip.presence
        if expected_checksum.blank? && checksum_path.present?
          expected_checksum = File.read(checksum_path).strip.split.first.to_s.strip.presence
        end

        if expected_checksum.present?
          actual_checksum = Digest::SHA256.file(bundle_path).hexdigest
          raise ArgumentError, "bundle checksum mismatch" unless actual_checksum == expected_checksum
        end

        map_statuses = lambda do |request_status|
          normalized = request_status.to_s.strip.downcase
          case normalized
          when "ok", "success", "succeeded"
            [ "succeeded", "succeeded" ]
          when "error", "failed"
            [ "failed", "failed" ]
          when "resent"
            [ "started", "pending" ]
          else
            [ "started", "pending" ]
          end
        end

        parse_time = lambda do |value|
          next nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue StandardError
          nil
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

          unless type == "MedusaIngest"
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, message: "unsupported type" }
            next
          end

          dataset_key = attributes["dataset_key"].to_s.strip
          if dataset_key.blank?
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, message: "missing dataset_key" }
            next
          end

          dataset = Dataset.find_by(key: dataset_key)
          if dataset.nil?
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, dataset_key: dataset_key, message: "dataset not found" }
            next
          end

          line_count += 1
          type_counts[type] += 1

          request_status = attributes["request_status"].to_s
          attempt_status, response_status = map_statuses.call(request_status)
          correlation_key = attributes["staging_key"].to_s.strip.presence || "legacy.medusa_ingest:#{attributes['legacy_id'] || line_number}"
          idempotency_key = "legacy.medusa_ingest:#{attributes['legacy_id'] || dataset.id}:#{line_number}"
          response_received_at = parse_time.call(attributes["response_time"])

          response_payload = {
            "status" => response_status == "succeeded" ? "ok" : (response_status == "failed" ? "error" : "pending"),
            "request_status" => request_status,
            "staging_key" => attributes["staging_key"],
            "target_key" => attributes["target_key"],
            "medusa_path" => attributes["medusa_path"],
            "uuid" => attributes["medusa_uuid"]
          }.compact

          values = {
            dataset: dataset,
            integration: :ingest,
            event_name: "dataset.published",
            status: attempt_status,
            attempt: 1,
            idempotency_key: idempotency_key,
            correlation_key: correlation_key,
            response_status: response_status,
            response_received_at: response_received_at,
            response_staging_key: attributes["staging_key"],
            response_target_key: attributes["target_key"],
            response_uuid: attributes["medusa_uuid"],
            response_payload: response_payload,
            error_class: response_status == "failed" ? "LegacyMedusaIngestError" : nil,
            error_message: attributes["error_text"].to_s.presence,
            details: {
              "legacy" => {
                "source" => "medusa_ingests_bundle",
                "legacy_id" => attributes["legacy_id"],
                "idb_class" => attributes["idb_class"],
                "idb_identifier" => attributes["idb_identifier"],
                "staging_path" => attributes["staging_path"],
                "medusa_dataset_dir" => attributes["medusa_dataset_dir"],
                "created_at" => attributes["created_at"],
                "updated_at" => attributes["updated_at"]
              }
            }
          }

          existing = ExternalDeliveryAttempt.find_by(integration: :ingest, correlation_key: correlation_key)
          if dry_run
            status = existing.nil? ? :would_create : :would_update
            summary[status] += 1
            summary[:records] << { line: line_number, status: status, type: type, dataset_key: dataset_key, correlation_key: correlation_key }
            next
          end

          if existing.nil?
            record = ExternalDeliveryAttempt.new(values)
            if record.save
              summary[:created] += 1
              summary[:records] << { line: line_number, status: :created, type: type, dataset_key: dataset_key, correlation_key: correlation_key }
            else
              summary[:failed] += 1
              summary[:records] << { line: line_number, status: :failed, type: type, dataset_key: dataset_key, correlation_key: correlation_key, message: record.errors.full_messages.to_sentence }
            end
          elsif existing.update(values.except(:dataset, :integration, :event_name))
            summary[:updated] += 1
            summary[:records] << { line: line_number, status: :updated, type: type, dataset_key: dataset_key, correlation_key: correlation_key }
          else
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, dataset_key: dataset_key, correlation_key: correlation_key, message: existing.errors.full_messages.to_sentence }
          end
        rescue JSON::ParserError => e
          summary[:failed] += 1
          summary[:records] << { line: line_number, status: :failed, message: "invalid JSON: #{e.message}" }
        end

        if manifest_data&.dig("record_count").present?
          expected_count = manifest_data["record_count"].to_i
          skipped_count = expected_count - line_count
          # Log warning if there's a significant mismatch, but don't fail
          # Some records may be skipped if their datasets don't exist in the target database
          if skipped_count > 0
            puts "Warning: #{skipped_count} medusa ingest records from manifest were skipped (dataset not found or invalid)"
          end
        end

        if manifest_data&.dig("counts").is_a?(Hash)
          expected_total = manifest_data["counts"]["MedusaIngest"]
          if expected_total.present?
            skipped_count = expected_total.to_i - line_count
            if skipped_count > 0
              puts "Warning: #{skipped_count} MedusaIngest records were skipped due to missing datasets"
            end
          end
        end

        summary[:processed_count] = line_count
        summary[:expected_record_count] = manifest_data&.dig("record_count")
        summary[:checksum] = expected_checksum
        summary[:counts] = type_counts

        Migration::RunReportWriter.new(
          report_path: resolved_report_path,
          report: {
            generated_at: Time.current.utc.iso8601,
            import_type: "medusa_ingests_bundle",
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
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
      if summary[:counts].is_a?(Hash)
        puts "MedusaIngest records processed: #{summary[:counts].fetch('MedusaIngest', 0)}"
      end
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

  namespace :download_metrics do
    desc "Import legacy download metrics bundle into tally records"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_download_metrics.ndjson")
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
        run_type: "download_metrics_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run
        }
      ) do
        raise ArgumentError, "bundle not found: #{bundle_path}" unless bundle_path.file?
        raise ArgumentError, "checksum file not found: #{checksum_path}" if checksum_path.present? && !File.file?(checksum_path)
        raise ArgumentError, "manifest file not found: #{manifest_path}" if manifest_path.present? && !File.file?(manifest_path)

        manifest_data = manifest_path.present? ? JSON.parse(File.read(manifest_path)) : nil
        expected_checksum = manifest_data&.dig("sha256").to_s.strip.presence
        if expected_checksum.blank? && checksum_path.present?
          expected_checksum = File.read(checksum_path).strip.split.first.to_s.strip.presence
        end

        if expected_checksum.present?
          actual_checksum = Digest::SHA256.file(bundle_path).hexdigest
          raise ArgumentError, "bundle checksum mismatch" unless actual_checksum == expected_checksum
        end

        parse_date = lambda do |value|
          next nil if value.blank?

          Date.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        parse_time = lambda do |value|
          next nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue StandardError
          nil
        end

        normalize_tally = lambda do |value|
          Integer(value)
        rescue ArgumentError, TypeError
          nil
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

          case type
          when "DatasetDownloadTally"
            download_date = parse_date.call(attributes["download_date"])
            tally = normalize_tally.call(attributes["tally"])

            if attributes["dataset_key"].to_s.blank? || download_date.nil? || tally.nil? || tally.negative?
              summary[:failed] += 1
              summary[:records] << { line: line_number, status: :failed, type: type, message: "invalid dataset download tally attributes" }
              next
            end

            finder = {
              dataset_key: attributes["dataset_key"].to_s,
              download_date: download_date
            }
            values = {
              doi: attributes["doi"],
              tally: tally,
              created_at: parse_time.call(attributes["created_at"]),
              updated_at: parse_time.call(attributes["updated_at"])
            }.compact
            model_class = DatasetDownloadTally
          when "FileDownloadTally"
            download_date = parse_date.call(attributes["download_date"])
            tally = normalize_tally.call(attributes["tally"])

            if attributes["file_web_id"].to_s.blank? || download_date.nil? || tally.nil? || tally.negative?
              summary[:failed] += 1
              summary[:records] << { line: line_number, status: :failed, type: type, message: "invalid file download tally attributes" }
              next
            end

            finder = {
              file_web_id: attributes["file_web_id"].to_s,
              download_date: download_date
            }
            values = {
              filename: attributes["filename"],
              dataset_key: attributes["dataset_key"],
              doi: attributes["doi"],
              tally: tally,
              created_at: parse_time.call(attributes["created_at"]),
              updated_at: parse_time.call(attributes["updated_at"])
            }.compact
            model_class = FileDownloadTally
          when "DayFileDownload"
            download_date = parse_date.call(attributes["download_date"])

            if attributes["ip_address"].to_s.blank? || attributes["file_web_id"].to_s.blank? || attributes["dataset_key"].to_s.blank? || download_date.nil?
              summary[:failed] += 1
              summary[:records] << { line: line_number, status: :failed, type: type, message: "invalid day file download attributes" }
              next
            end

            finder = {
              ip_address: attributes["ip_address"].to_s,
              file_web_id: attributes["file_web_id"].to_s,
              download_date: download_date
            }
            values = {
              filename: attributes["filename"],
              dataset_key: attributes["dataset_key"],
              doi: attributes["doi"],
              created_at: parse_time.call(attributes["created_at"]),
              updated_at: parse_time.call(attributes["updated_at"])
            }.compact
            model_class = DayFileDownload
          else
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, message: "unsupported type" }
            next
          end

          line_count += 1
          type_counts[type] += 1

          existing = model_class.find_by(finder)
          comparable_values = values.transform_keys(&:to_s)

          if dry_run
            status = if existing.nil?
              :would_create
            elsif comparable_values.all? { |key, value| existing.public_send(key) == value }
              :skipped_existing
            else
              :would_update
            end

            summary[status] += 1
            summary[:records] << { line: line_number, status: status, type: type }.merge(finder)
            next
          end

          if existing.nil?
            record = model_class.new(finder.merge(values))
            if record.save
              summary[:created] += 1
              summary[:records] << { line: line_number, status: :created, type: type }.merge(finder)
            else
              summary[:failed] += 1
              summary[:records] << { line: line_number, status: :failed, type: type, message: record.errors.full_messages.to_sentence }.merge(finder)
            end
          elsif comparable_values.all? { |key, value| existing.public_send(key) == value }
            summary[:skipped_existing] += 1
            summary[:records] << { line: line_number, status: :skipped_existing, type: type }.merge(finder)
          elsif existing.update(values)
            summary[:updated] += 1
            summary[:records] << { line: line_number, status: :updated, type: type }.merge(finder)
          else
            summary[:failed] += 1
            summary[:records] << { line: line_number, status: :failed, type: type, message: existing.errors.full_messages.to_sentence }.merge(finder)
          end
        rescue JSON::ParserError => e
          summary[:failed] += 1
          summary[:records] << { line: line_number, status: :failed, message: "invalid JSON: #{e.message}" }
        end

        if manifest_data&.dig("record_count").present?
          expected_count = manifest_data["record_count"].to_i
          raise ArgumentError, "bundle record count mismatch" if expected_count != line_count
        end

        if manifest_data&.dig("counts").is_a?(Hash)
          %w[DatasetDownloadTally FileDownloadTally DayFileDownload].each do |record_type|
            expected = manifest_data["counts"][record_type]
            next if expected.nil?

            raise ArgumentError, "manifest count mismatch for #{record_type}" if type_counts[record_type].to_i != expected.to_i
          end
        end

        summary[:processed_count] = line_count
        summary[:expected_record_count] = manifest_data&.dig("record_count")
        summary[:checksum] = expected_checksum
        summary[:counts] = {
          "DatasetDownloadTally" => type_counts["DatasetDownloadTally"].to_i,
          "FileDownloadTally" => type_counts["FileDownloadTally"].to_i,
          "DayFileDownload" => type_counts["DayFileDownload"].to_i
        }

        Migration::RunReportWriter.new(
          report_path: resolved_report_path,
          report: {
            generated_at: Time.current.utc.iso8601,
            import_type: "download_metrics_bundle",
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
      puts "Created: #{summary[:created]}, Updated: #{summary[:updated]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      if dry_run
        puts "Dry run only - Would create: #{summary[:would_create]}, Would update: #{summary[:would_update]}"
      end
      if summary[:counts].is_a?(Hash)
        puts "DatasetDownloadTally records processed: #{summary[:counts].fetch('DatasetDownloadTally', 0)}"
        puts "FileDownloadTally records processed: #{summary[:counts].fetch('FileDownloadTally', 0)}"
        puts "DayFileDownload records processed: #{summary[:counts].fetch('DayFileDownload', 0)}"
      end
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

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
      if summary[:relationship_reconciliation].is_a?(Hash)
        metrics = summary[:relationship_reconciliation]
        puts "Relationship assertions exported: #{metrics[:exported_total_assertions]}"
        puts "Relationship assertions imported: #{metrics[:imported_total_assertions]}" if metrics[:enabled]
        puts "Relationship assertion strict match: #{metrics[:strict_match]}" if metrics[:enabled]
        puts "Relationship assertion mismatched datasets: #{metrics[:mismatched_dataset_count]}" if metrics[:enabled]
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
      if summary[:relationship_reconciliation].is_a?(Hash)
        metrics = summary[:relationship_reconciliation]
        puts "Relationship assertions exported: #{metrics[:exported_total_assertions]}"
        puts "Relationship assertions imported: #{metrics[:imported_total_assertions]}" if metrics[:enabled]
        puts "Relationship assertion strict match: #{metrics[:strict_match]}" if metrics[:enabled]
        puts "Relationship assertion mismatched datasets: #{metrics[:mismatched_dataset_count]}" if metrics[:enabled]
      end
    end
  end

  namespace :flat_bundle do
    desc "Import flat NDJSON bundle (format_version: 2) with separate entity records"
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
        run_type: "flat_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run,
          overwrite: overwrite
        }
      ) do
        Migration::FlatBundleImportService.new(
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
      puts "Datasets: #{summary[:record_counts][:datasets]}" if summary[:record_counts]
      puts "Datafiles: #{summary[:record_counts][:datafiles]}" if summary[:record_counts]
      puts "Nested items: #{summary[:record_counts][:nested_items]}" if summary[:record_counts]
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
    end
  end

  namespace :audits do
    desc "Import a secure NDJSON audit bundle exported from legacy databank"
    task import: :environment do
      bundle_path = ENV.fetch("BUNDLE")
      checksum_path = ENV["CHECKSUM"]
      manifest_path = ENV["MANIFEST"]
      report_path = ENV["REPORT_FILE"].presence
      resolved_report_path = migration_report_path(Pathname(bundle_path).dirname, report_path)
      dry_run = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?

      summary = record_migration_run(
        run_type: "audits_bundle_import",
        bundle_path: bundle_path,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run
        }
      ) do
        Migration::AuditsBundleImportService.new(
          bundle_path: bundle_path,
          dry_run: dry_run,
          checksum_path: checksum_path,
          manifest_path: manifest_path,
          report_path: resolved_report_path.to_s
        ).call
      end

      puts "Bundle: #{summary[:bundle_path]}"
      puts "Report: #{resolved_report_path}"
      puts "Created: #{summary[:created]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
      puts "Dry run only - Would create: #{summary[:would_create]}" if dry_run
    end

    desc "Import copied legacy audit export artifacts from a directory"
    task import_from_dir: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_audits.ndjson")
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
        run_type: "audits_bundle_import",
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run
        }
      ) do
        Migration::AuditsBundleImportService.new(
          bundle_path: bundle_path.to_s,
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
      puts "Created: #{summary[:created]}, Skipped: #{summary[:skipped_existing]}, Failed: #{summary[:failed]}"
      puts "Validation error: #{summary[:validation_error]}" if summary[:validation_error].present?
      puts "Dry run only - Would create: #{summary[:would_create]}" if dry_run
    end
  end
end
