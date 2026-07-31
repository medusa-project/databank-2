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
      resume_from_line = ENV.fetch("DOWNLOAD_METRICS_IMPORT_RESUME_FROM_LINE", "1").to_i
      max_records_window = ENV["DOWNLOAD_METRICS_IMPORT_MAX_RECORDS"].to_i
      max_records_window = nil if max_records_window <= 0
      checkpoint_file = ENV["DOWNLOAD_METRICS_IMPORT_CHECKPOINT_FILE"].to_s.strip
      checkpoint_path = if checkpoint_file.present?
        candidate = Pathname(checkpoint_file)
        candidate = dir.join(candidate) unless candidate.absolute?
        candidate
      end
      windowed_import = resume_from_line > 1 || max_records_window.present?

      if resume_from_line <= 0
        raise ArgumentError, "DOWNLOAD_METRICS_IMPORT_RESUME_FROM_LINE must be positive"
      end

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
        if manifest_data&.dig("format_version").present? && manifest_data["format_version"].to_i != 1
          raise ArgumentError, "unsupported download metrics bundle format_version"
        end

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
        processed_in_window = 0
        stopped_early = false
        last_seen_line = resume_from_line - 1

        File.foreach(bundle_path).with_index(1) do |line, line_number|
          next if line_number < resume_from_line

          if max_records_window.present? && processed_in_window >= max_records_window
            stopped_early = true
            break
          end

          next if line.strip.empty?

          processed_in_window += 1
          last_seen_line = line_number

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

        if !windowed_import && manifest_data&.dig("record_count").present?
          expected_count = manifest_data["record_count"].to_i
          raise ArgumentError, "bundle record count mismatch" if expected_count != line_count
        end

        if !windowed_import && manifest_data&.dig("counts").is_a?(Hash)
          %w[DatasetDownloadTally FileDownloadTally DayFileDownload].each do |record_type|
            expected = manifest_data["counts"][record_type]
            next if expected.nil?

            raise ArgumentError, "manifest count mismatch for #{record_type}" if type_counts[record_type].to_i != expected.to_i
          end
        end

        next_resume_from_line = [ last_seen_line + 1, resume_from_line ].max

        summary[:processed_count] = line_count
        summary[:expected_record_count] = manifest_data&.dig("record_count")
        summary[:checksum] = expected_checksum
        summary[:manifest_format_version] = manifest_data&.dig("format_version")
        summary[:include_tests] = manifest_data&.dig("include_tests") unless manifest_data.nil?
        summary[:since] = manifest_data&.dig("since")
        summary[:until] = manifest_data&.dig("until")
        summary[:counts] = {
          "DatasetDownloadTally" => type_counts["DatasetDownloadTally"].to_i,
          "FileDownloadTally" => type_counts["FileDownloadTally"].to_i,
          "DayFileDownload" => type_counts["DayFileDownload"].to_i
        }
        summary[:windowed_import] = windowed_import
        summary[:resume_from_line] = resume_from_line
        summary[:max_records_window] = max_records_window
        summary[:next_resume_from_line] = next_resume_from_line
        summary[:stopped_early] = stopped_early

        if checkpoint_path.present?
          checkpoint_path.dirname.mkpath
          checkpoint_payload = {
            generated_at: Time.current.utc.iso8601,
            next_resume_from_line: next_resume_from_line,
            stopped_early: stopped_early,
            summary: {
              created: summary[:created],
              updated: summary[:updated],
              skipped_existing: summary[:skipped_existing],
              failed: summary[:failed],
              processed_count: summary[:processed_count],
              counts: summary[:counts],
              validation_error: summary[:validation_error]
            }
          }
          File.write(checkpoint_path, JSON.pretty_generate(checkpoint_payload))
        end

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

    desc "Run download metrics import in bounded resumable windows using checkpoint state"
    task import_in_chunks: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_download_metrics.ndjson")
      report_file = ENV.fetch("REPORT_FILE", "download_metrics_chunk.report.json")
      checkpoint_file = ENV.fetch("CHECKPOINT_FILE", "download_metrics_import.checkpoint.json")
      lock_file = ENV.fetch("LOCK_FILE", "download_metrics_import.lock")

      max_records = ENV.fetch("MAX_RECORDS", "50000").to_i
      max_iterations = ENV.fetch("MAX_ITERATIONS", "100").to_i
      max_minutes = ENV.fetch("MAX_MINUTES", "240").to_i
      max_consecutive_failures = ENV.fetch("MAX_CONSECUTIVE_FAILURES", "5").to_i
      max_stalled_runs = ENV.fetch("MAX_STALLED_RUNS", "2").to_i
      resume_overlap = ENV.fetch("RESUME_OVERLAP_LINES", "0").to_i

      raise ArgumentError, "MAX_RECORDS must be positive" if max_records <= 0
      raise ArgumentError, "MAX_ITERATIONS must be positive" if max_iterations <= 0
      raise ArgumentError, "MAX_MINUTES must be positive" if max_minutes <= 0
      raise ArgumentError, "MAX_CONSECUTIVE_FAILURES must be positive" if max_consecutive_failures <= 0
      raise ArgumentError, "MAX_STALLED_RUNS must be positive" if max_stalled_runs <= 0

      checkpoint_path = Pathname(checkpoint_file)
      checkpoint_path = dir.join(checkpoint_path) unless checkpoint_path.absolute?
      report_path = Pathname(report_file)
      report_path = dir.join(report_path) unless report_path.absolute?
      lock_path = Pathname(lock_file)
      lock_path = dir.join(lock_path) unless lock_path.absolute?

      FileUtils.mkdir_p(dir)

      lock_handle = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
      unless lock_handle.flock(File::LOCK_EX | File::LOCK_NB)
        raise "Chunked download metrics import is already running (lock: #{lock_path})"
      end

      started_at = Time.current
      deadline = started_at + max_minutes.minutes

      iteration = 0
      consecutive_failures = 0
      stalled_runs = 0
      previous_next_resume = nil
      completed = false
      last_summary = nil

      begin
        while Time.current <= deadline && iteration < max_iterations
          iteration += 1

          next_resume_line = 1
          if checkpoint_path.file?
            checkpoint = JSON.parse(File.read(checkpoint_path))
            candidate = checkpoint["next_resume_from_line"].to_i
            next_resume_line = candidate if candidate.positive?
          end

          if resume_overlap.positive? && next_resume_line > resume_overlap
            next_resume_line -= resume_overlap
          end

          puts "Chunk #{iteration}: resume_from_line=#{next_resume_line}, max_records=#{max_records}"

          previous_env = {
            "DIR" => ENV["DIR"],
            "BUNDLE_FILE" => ENV["BUNDLE_FILE"],
            "REPORT_FILE" => ENV["REPORT_FILE"],
            "DOWNLOAD_METRICS_IMPORT_RESUME_FROM_LINE" => ENV["DOWNLOAD_METRICS_IMPORT_RESUME_FROM_LINE"],
            "DOWNLOAD_METRICS_IMPORT_MAX_RECORDS" => ENV["DOWNLOAD_METRICS_IMPORT_MAX_RECORDS"],
            "DOWNLOAD_METRICS_IMPORT_CHECKPOINT_FILE" => ENV["DOWNLOAD_METRICS_IMPORT_CHECKPOINT_FILE"]
          }

          begin
            ENV["DIR"] = dir.to_s
            ENV["BUNDLE_FILE"] = bundle_file
            ENV["REPORT_FILE"] = report_path.to_s
            ENV["DOWNLOAD_METRICS_IMPORT_RESUME_FROM_LINE"] = next_resume_line.to_s
            ENV["DOWNLOAD_METRICS_IMPORT_MAX_RECORDS"] = max_records.to_s
            ENV["DOWNLOAD_METRICS_IMPORT_CHECKPOINT_FILE"] = checkpoint_path.to_s

            task = Rake::Task["migration:download_metrics:import_from_dir"]
            task.reenable
            task.invoke
          ensure
            previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
          end

          raise "checkpoint file not written: #{checkpoint_path}" unless checkpoint_path.file?

          checkpoint = JSON.parse(File.read(checkpoint_path))
          next_resume = checkpoint["next_resume_from_line"].to_i
          stopped_early = checkpoint["stopped_early"]
          last_summary = checkpoint["summary"] || {}

          raise "invalid checkpoint next_resume_from_line: #{next_resume.inspect}" if next_resume <= 0

          if previous_next_resume.present? && next_resume <= previous_next_resume
            stalled_runs += 1
            warn "No checkpoint progress detected (#{stalled_runs}/#{max_stalled_runs})"
          else
            stalled_runs = 0
          end
          previous_next_resume = next_resume

          if last_summary["validation_error"].present?
            consecutive_failures += 1
            warn "Chunk #{iteration} validation error (#{consecutive_failures}/#{max_consecutive_failures}): #{last_summary['validation_error']}"
          else
            consecutive_failures = 0
          end

          if stalled_runs >= max_stalled_runs
            warn "Stopping due to stalled checkpoint progress"
            break
          end

          if consecutive_failures >= max_consecutive_failures
            warn "Stopping due to consecutive validation errors"
            break
          end

          unless stopped_early
            completed = true
            puts "Chunk loop complete: end-of-file reached"
            break
          end
        end

        warn "Stopping due to MAX_MINUTES ceiling" if Time.current > deadline
        warn "Stopping due to MAX_ITERATIONS ceiling" if iteration >= max_iterations && !completed

        puts "Chunk loop summary: completed=#{completed}, iterations=#{iteration}, consecutive_failures=#{consecutive_failures}, stalled_runs=#{stalled_runs}"
        if last_summary.is_a?(Hash)
          puts "Last chunk: failed=#{last_summary['failed']}, dataset_download_tallies=#{last_summary.dig('counts', 'DatasetDownloadTally')}, file_download_tallies=#{last_summary.dig('counts', 'FileDownloadTally')}, day_file_downloads=#{last_summary.dig('counts', 'DayFileDownload')}"
        end
      ensure
        lock_handle.flock(File::LOCK_UN)
        lock_handle.close
      end
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
    # Deprecated: legacy non-flat bundle import path. Prefer migration:flat_bundle:* tasks.
    desc "[DEPRECATED] Import a secure NDJSON migration bundle exported from legacy databank"
    task import: :environment do
      warn "DEPRECATED: migration:bundle:import is non-flat. Prefer migration:flat_bundle:import_from_dir or migration:flat_bundle:import_in_chunks."
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

    desc "[DEPRECATED] Import copied legacy export artifacts from a directory"
    task import_from_dir: :environment do
      warn "DEPRECATED: migration:bundle:import_from_dir is non-flat. Prefer migration:flat_bundle:import_from_dir or migration:flat_bundle:import_in_chunks."
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
      import_mode = ENV.fetch("IMPORT_MODE", Migration::FlatBundleImportService::IMPORT_MODE_ALL)
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
      run_type = case import_mode
      when Migration::FlatBundleImportService::IMPORT_MODE_STRUCTURE_ONLY
        "flat_bundle_structure_import"
      when Migration::FlatBundleImportService::IMPORT_MODE_NESTED_ITEMS_ONLY
        "flat_bundle_nested_items_import"
      else
        "flat_bundle_import"
      end

      summary = record_migration_run(
        run_type: run_type,
        bundle_path: bundle_path.to_s,
        checksum_path: checksum_path,
        manifest_path: manifest_path,
        report_path: resolved_report_path.to_s,
        details: {
          dry_run: dry_run,
          overwrite: overwrite,
          import_mode: import_mode
        }
      ) do
        service_kwargs = {
          bundle_path: bundle_path.to_s,
          overwrite: overwrite,
          dry_run: dry_run,
          checksum_path: checksum_path,
          manifest_path: manifest_path,
          report_path: resolved_report_path.to_s
        }
        service_kwargs[:import_mode] = import_mode unless import_mode == Migration::FlatBundleImportService::IMPORT_MODE_ALL

        Migration::FlatBundleImportService.new(
          **service_kwargs
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

    desc "Import only dataset/datafile records from a flat NDJSON bundle"
    task import_structure_from_dir: :environment do
      old_mode = ENV["IMPORT_MODE"]
      ENV["IMPORT_MODE"] = Migration::FlatBundleImportService::IMPORT_MODE_STRUCTURE_ONLY
      task = Rake::Task["migration:flat_bundle:import_from_dir"]
      task.reenable
      task.invoke
    ensure
      old_mode.nil? ? ENV.delete("IMPORT_MODE") : ENV["IMPORT_MODE"] = old_mode
    end

    desc "Import only nested_item records from a flat NDJSON bundle"
    task import_nested_items_from_dir: :environment do
      old_mode = ENV["IMPORT_MODE"]
      ENV["IMPORT_MODE"] = Migration::FlatBundleImportService::IMPORT_MODE_NESTED_ITEMS_ONLY
      task = Rake::Task["migration:flat_bundle:import_from_dir"]
      task.reenable
      task.invoke
    ensure
      old_mode.nil? ? ENV.delete("IMPORT_MODE") : ENV["IMPORT_MODE"] = old_mode
    end

    desc "Run flat bundle import in bounded resumable windows using checkpoint state"
    task import_in_chunks: :environment do
      dir = Pathname(ENV.fetch("DIR"))
      import_mode = ENV.fetch("IMPORT_MODE", Migration::FlatBundleImportService::IMPORT_MODE_ALL)
      bundle_file = ENV.fetch("BUNDLE_FILE", "legacy_datasets.ndjson")
      default_checkpoint_file = case import_mode
      when Migration::FlatBundleImportService::IMPORT_MODE_STRUCTURE_ONLY
        "flat_bundle_structure_import.checkpoint.json"
      when Migration::FlatBundleImportService::IMPORT_MODE_NESTED_ITEMS_ONLY
        "flat_bundle_nested_items_import.checkpoint.json"
      else
        "flat_bundle_import.checkpoint.json"
      end
      checkpoint_file = ENV.fetch("CHECKPOINT_FILE", default_checkpoint_file)
      report_file = ENV.fetch("REPORT_FILE", "import_report.json")
      max_records = ENV.fetch("MAX_RECORDS", "50000")
      max_iterations = ENV.fetch("MAX_ITERATIONS", "100").to_i
      max_minutes = ENV.fetch("MAX_MINUTES", "240").to_i
      max_consecutive_failures = ENV.fetch("MAX_CONSECUTIVE_FAILURES", "5").to_i
      max_stalled_runs = ENV.fetch("MAX_STALLED_RUNS", "2").to_i
      resume_overlap = ENV.fetch("RESUME_OVERLAP_LINES", "200").to_i
      backoff_base_seconds = ENV.fetch("BACKOFF_BASE_SECONDS", "10").to_i
      lock_file = ENV.fetch("LOCK_FILE", "flat_bundle_import.lock")

      checkpoint_path = Pathname(checkpoint_file)
      checkpoint_path = dir.join(checkpoint_path) unless checkpoint_path.absolute?
      report_path = Pathname(report_file)
      report_path = dir.join(report_path) unless report_path.absolute?
      lock_path = Pathname(lock_file)
      lock_path = dir.join(lock_path) unless lock_path.absolute?

      if max_iterations <= 0
        raise ArgumentError, "MAX_ITERATIONS must be positive"
      end
      if max_minutes <= 0
        raise ArgumentError, "MAX_MINUTES must be positive"
      end
      if max_consecutive_failures <= 0
        raise ArgumentError, "MAX_CONSECUTIVE_FAILURES must be positive"
      end
      if max_stalled_runs <= 0
        raise ArgumentError, "MAX_STALLED_RUNS must be positive"
      end

      FileUtils.mkdir_p(dir)

      lock_handle = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
      unless lock_handle.flock(File::LOCK_EX | File::LOCK_NB)
        raise "Chunked flat import is already running (lock: #{lock_path})"
      end

      started_at = Time.current
      deadline = started_at + max_minutes.minutes
      iteration = 0
      consecutive_failures = 0
      stalled_runs = 0
      previous_next_resume = nil
      completed = false
      last_summary = nil

      begin
        while Time.current <= deadline && iteration < max_iterations
          iteration += 1

          next_resume_line = 1
          if checkpoint_path.file?
            checkpoint = JSON.parse(File.read(checkpoint_path))
            candidate = checkpoint["next_resume_from_line"].to_i
            next_resume_line = candidate if candidate.positive?
          end

          next_resume_line = [ next_resume_line - resume_overlap, 1 ].max

          puts "Chunk #{iteration}: resume_from_line=#{next_resume_line}, max_records=#{max_records}"

          previous_env = {
            "FLAT_BUNDLE_IMPORT_RESUME_FROM_LINE" => ENV["FLAT_BUNDLE_IMPORT_RESUME_FROM_LINE"],
            "FLAT_BUNDLE_IMPORT_MAX_RECORDS" => ENV["FLAT_BUNDLE_IMPORT_MAX_RECORDS"],
            "FLAT_BUNDLE_IMPORT_CHECKPOINT_FILE" => ENV["FLAT_BUNDLE_IMPORT_CHECKPOINT_FILE"],
            "IMPORT_MODE" => ENV["IMPORT_MODE"],
            "REPORT_FILE" => ENV["REPORT_FILE"],
            "DIR" => ENV["DIR"],
            "BUNDLE_FILE" => ENV["BUNDLE_FILE"]
          }

          begin
            ENV["DIR"] = dir.to_s
            ENV["BUNDLE_FILE"] = bundle_file
            ENV["REPORT_FILE"] = report_path.to_s
            ENV["FLAT_BUNDLE_IMPORT_RESUME_FROM_LINE"] = next_resume_line.to_s
            ENV["FLAT_BUNDLE_IMPORT_MAX_RECORDS"] = max_records.to_s
            ENV["FLAT_BUNDLE_IMPORT_CHECKPOINT_FILE"] = checkpoint_path.to_s
            ENV["IMPORT_MODE"] = import_mode

            task = Rake::Task["migration:flat_bundle:import_from_dir"]
            task.reenable
            task.invoke
          ensure
            previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
          end

          unless checkpoint_path.file?
            raise "checkpoint file not written: #{checkpoint_path}"
          end

          checkpoint = JSON.parse(File.read(checkpoint_path))
          next_resume = checkpoint["next_resume_from_line"].to_i
          stopped_early = checkpoint["stopped_early"]
          last_summary = checkpoint["summary"] || {}

          if next_resume <= 0
            raise "invalid checkpoint next_resume_from_line: #{next_resume.inspect}"
          end

          if previous_next_resume.present? && next_resume <= previous_next_resume
            stalled_runs += 1
            warn "No checkpoint progress detected (#{stalled_runs}/#{max_stalled_runs})"
          else
            stalled_runs = 0
          end
          previous_next_resume = next_resume

          if last_summary["validation_error"].present?
            consecutive_failures += 1
            warn "Chunk #{iteration} validation error (#{consecutive_failures}/#{max_consecutive_failures}): #{last_summary['validation_error']}"
          else
            consecutive_failures = 0
          end

          if stalled_runs >= max_stalled_runs
            warn "Stopping due to stalled checkpoint progress"
            break
          end

          if consecutive_failures >= max_consecutive_failures
            warn "Stopping due to consecutive validation errors"
            break
          end

          unless stopped_early
            completed = true
            puts "Chunk loop complete: end-of-file reached"
            break
          end

          if consecutive_failures.positive?
            sleep_seconds = backoff_base_seconds * (2**(consecutive_failures - 1))
            puts "Backing off for #{sleep_seconds}s before next chunk"
            sleep(sleep_seconds)
          end
        end

        if Time.current > deadline
          warn "Stopping due to MAX_MINUTES ceiling"
        elsif iteration >= max_iterations && !completed
          warn "Stopping due to MAX_ITERATIONS ceiling"
        end

        puts "Chunk loop summary: completed=#{completed}, iterations=#{iteration}, consecutive_failures=#{consecutive_failures}, stalled_runs=#{stalled_runs}"
        if last_summary.is_a?(Hash)
          puts "Last chunk: failed=#{last_summary['failed']}, datasets=#{last_summary['datasets']}, datafiles=#{last_summary['datafiles']}, nested_items=#{last_summary['nested_items']}"
        end
      ensure
        lock_handle.flock(File::LOCK_UN)
        lock_handle.close
      end
    end

    desc "Run dataset/datafile-only import in bounded resumable windows"
    task import_structure_in_chunks: :environment do
      old_mode = ENV["IMPORT_MODE"]
      ENV["IMPORT_MODE"] = Migration::FlatBundleImportService::IMPORT_MODE_STRUCTURE_ONLY
      task = Rake::Task["migration:flat_bundle:import_in_chunks"]
      task.reenable
      task.invoke
    ensure
      old_mode.nil? ? ENV.delete("IMPORT_MODE") : ENV["IMPORT_MODE"] = old_mode
    end

    desc "Run nested-items-only import in bounded resumable windows"
    task import_nested_items_in_chunks: :environment do
      old_mode = ENV["IMPORT_MODE"]
      ENV["IMPORT_MODE"] = Migration::FlatBundleImportService::IMPORT_MODE_NESTED_ITEMS_ONLY
      task = Rake::Task["migration:flat_bundle:import_in_chunks"]
      task.reenable
      task.invoke
    ensure
      old_mode.nil? ? ENV.delete("IMPORT_MODE") : ENV["IMPORT_MODE"] = old_mode
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
