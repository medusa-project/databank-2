require "json"
require "digest"
require "set"

module Migration
  class FeaturedResearchersBundleImportService
    attr_reader :bundle_path, :dry_run, :checksum_path, :manifest_path, :replace_all, :overwrite, :report_path

    VALID_TYPE = "FeaturedResearcher".freeze

    def initialize(bundle_path:, dry_run: false, checksum_path: nil, manifest_path: nil, replace_all: true, overwrite: false, report_path: nil)
      @bundle_path = Pathname(bundle_path)
      @dry_run = dry_run
      @checksum_path = checksum_path.present? ? Pathname(checksum_path) : nil
      @manifest_path = manifest_path.present? ? Pathname(manifest_path) : nil
      @replace_all = replace_all
      @overwrite = overwrite
      @report_path = resolve_report_path(report_path)
    end

    def call
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

      validate_paths!
      verify_bundle_integrity!

      payloads = parse_payloads(summary)
      verify_expected_record_count!(payloads.size)
      verify_manifest_counts!(payloads)
      verify_unique_ids!(payloads)

      if dry_run
        payloads.each_with_index do |payload, idx|
          status = dry_run_status(payload)
          increment_summary(summary, status)
          summary[:records] << { line: idx + 1, status: status, id: payload.dig("attributes", "id") }
        end
        summary[:processed_count] = payloads.size
        summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_count") }
        summary[:checksum] = safe_expected_checksum
        write_report_artifact!(summary)
        return summary
      end

      ActiveRecord::Base.transaction do
        clear_existing_featured_researchers! if replace_all

        payloads.each_with_index do |payload, idx|
          result = import_payload!(payload)
          increment_summary(summary, result[:status])
          summary[:records] << {
            line: idx + 1,
            status: result[:status],
            id: result[:id],
            name: result[:name],
            message: result[:message]
          }
        end

        reset_featured_researcher_sequence!
      end

      summary[:processed_count] = payloads.size
      summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_count") }
      summary[:checksum] = safe_expected_checksum
      write_report_artifact!(summary)

      summary
    rescue StandardError => e
      summary[:validation_error] = e.message if defined?(summary)
      summary[:failed] += 1 if defined?(summary)
      summary[:processed_count] = payloads&.size.to_i if defined?(summary)
      summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_count") } if defined?(summary)
      summary[:checksum] = safe_expected_checksum if defined?(summary)
      write_report_artifact!(summary) if defined?(summary)
      summary || {
        bundle_path: bundle_path.to_s,
        created: 0,
        updated: 0,
        skipped_existing: 0,
        would_create: 0,
        would_update: 0,
        failed: 1,
        validation_error: e.message,
        records: []
      }
    end

    private

    def validate_paths!
      raise ArgumentError, "bundle not found: #{bundle_path}" unless bundle_path.file?
      raise ArgumentError, "checksum file not found: #{checksum_path}" if checksum_path && !checksum_path.file?
      raise ArgumentError, "manifest file not found: #{manifest_path}" if manifest_path && !manifest_path.file?
    end

    def verify_bundle_integrity!
      expected = expected_checksum
      return if expected.blank?

      actual = Digest::SHA256.file(bundle_path).hexdigest
      return if secure_compare(actual, expected)

      raise ArgumentError, "bundle checksum mismatch"
    end

    def expected_checksum
      from_manifest = manifest_data["sha256"].to_s.strip if manifest_data
      return from_manifest if from_manifest.present?

      return nil unless checksum_path

      token = File.read(checksum_path).strip.split.first
      token&.strip
    end

    def parse_payloads(summary)
      payloads = []

      File.foreach(bundle_path).with_index(1) do |line, line_number|
        next if line.strip.empty?

        payload = JSON.parse(line)
        type = payload["type"].to_s
        attributes = payload["attributes"]

        unless type == VALID_TYPE
          raise ArgumentError, "unsupported spotlight record type at line #{line_number}: #{type}"
        end

        unless attributes.is_a?(Hash)
          raise ArgumentError, "missing attributes hash at line #{line_number}"
        end

        payloads << payload
      rescue JSON::ParserError => e
        summary[:records] << { line: line_number, status: :failed, message: "invalid JSON: #{e.message}" }
        raise ArgumentError, "invalid JSON at line #{line_number}"
      end

      payloads
    end

    def verify_expected_record_count!(processed_count)
      return unless manifest_data && manifest_data["record_count"].present?

      expected = manifest_data["record_count"].to_i
      return if expected == processed_count

      raise ArgumentError, "bundle record count mismatch"
    end

    def verify_manifest_counts!(payloads)
      return unless manifest_data && manifest_data["counts"].is_a?(Hash)

      expected = manifest_data["counts"][VALID_TYPE]
      return if expected.nil?

      actual = payloads.count
      return if expected.to_i == actual

      raise ArgumentError, "manifest count mismatch for #{VALID_TYPE}"
    end

    def verify_unique_ids!(payloads)
      ids = payloads.map { |payload| payload.dig("attributes", "id").to_i }
      duplicates = ids.tally.select { |_id, count| count > 1 }
      return if duplicates.empty?

      raise ArgumentError, "duplicate spotlight ids in bundle: #{duplicates.keys.sort.join(", ")}"
    end

    def dry_run_status(payload)
      return :would_create if replace_all

      attrs = payload.fetch("attributes")
      id = attrs.fetch("id").to_i
      existing = FeaturedResearcher.find_by(id: id)
      return :would_create if existing.nil?
      return :would_update if overwrite

      :skipped_existing
    end

    def import_payload!(payload)
      attrs = normalized_attributes(payload.fetch("attributes"))
      id = attrs.fetch(:id)

      if replace_all
        record = FeaturedResearcher.create!(attrs)
        return { status: :created, id: record.id, name: record.name, message: "created" }
      end

      record = FeaturedResearcher.find_by(id: id)
      if record.nil?
        record = FeaturedResearcher.create!(attrs)
        { status: :created, id: record.id, name: record.name, message: "created" }
      elsif overwrite
        record.update!(attrs.except(:id))
        { status: :updated, id: record.id, name: record.name, message: "updated" }
      else
        { status: :skipped_existing, id: record.id, name: record.name, message: "skipped existing" }
      end
    end

    def normalized_attributes(attrs)
      id = attrs.fetch("id").to_i
      raise ArgumentError, "invalid spotlight id: #{attrs["id"].inspect}" if id <= 0

      {
        id: id,
        name: squish_or_nil(attrs["name"]),
        question: squish_or_nil(attrs["question"]),
        testimonial: squish_or_nil(attrs["testimonial"]),
        bio: squish_or_nil(attrs["bio"]),
        photo_url: strip_or_nil(attrs["photo_url"]),
        dataset_url: strip_or_nil(attrs["dataset_url"]),
        article_url: strip_or_nil(attrs["article_url"]),
        is_active: ActiveModel::Type::Boolean.new.cast(attrs["is_active"]),
        created_at: parse_time!(attrs["created_at"], "created_at", id),
        updated_at: parse_time!(attrs["updated_at"], "updated_at", id)
      }
    end

    def strip_or_nil(value)
      str = value.to_s.strip
      str.present? ? str : nil
    end

    def squish_or_nil(value)
      str = value.to_s.strip
      str.present? ? str : nil
    end

    def parse_time!(value, field, id)
      raise ArgumentError, "missing #{field} for spotlight id=#{id}" if value.blank?

      parsed = Time.zone.parse(value.to_s)
      raise ArgumentError, "invalid #{field} for spotlight id=#{id}" if parsed.nil?

      parsed
    rescue ArgumentError
      raise ArgumentError, "invalid #{field} for spotlight id=#{id}"
    end

    def clear_existing_featured_researchers!
      FeaturedResearcher.delete_all
    end

    def reset_featured_researcher_sequence!
      ActiveRecord::Base.connection.reset_pk_sequence!(FeaturedResearcher.table_name)
    end

    def manifest_data
      return @manifest_data if defined?(@manifest_data)

      @manifest_data = manifest_path ? JSON.parse(File.read(manifest_path)) : nil
      if @manifest_data && @manifest_data["format_version"].present? && @manifest_data["format_version"].to_i != 1
        raise ArgumentError, "unsupported spotlights bundle format_version"
      end
      @manifest_data
    end

    def safe_manifest_value
      yield
    rescue StandardError
      nil
    end

    def safe_expected_checksum
      expected_checksum
    rescue StandardError
      nil
    end

    def default_report_path
      bundle_path.dirname.join("import_report.json")
    end

    def resolve_report_path(report_path)
      return default_report_path unless report_path.present?

      path = Pathname(report_path)
      path.absolute? ? path : bundle_path.dirname.join(path)
    end

    def write_report_artifact!(summary)
      Migration::RunReportWriter.new(
        report_path: report_path,
        report: {
          generated_at: Time.current.utc.iso8601,
          import_type: "featured_researchers_bundle",
          bundle_path: summary[:bundle_path],
          checksum_path: checksum_path&.to_s,
          manifest_path: manifest_path&.to_s,
          summary: summary
        }
      ).call
    rescue StandardError => e
      summary[:report_error] = e.message if summary.respond_to?(:[]=)
    end

    def secure_compare(a, b)
      return false if a.bytesize != b.bytesize

      l = a.unpack("C*")
      r = b.unpack("C*")
      result = 0
      l.zip(r) { |x, y| result |= (x ^ y) }
      result.zero?
    end

    def increment_summary(summary, status)
      case status
      when :created then summary[:created] += 1
      when :updated then summary[:updated] += 1
      when :skipped_existing then summary[:skipped_existing] += 1
      when :would_create then summary[:would_create] += 1
      when :would_update then summary[:would_update] += 1
      else
        summary[:failed] += 1
      end
    end
  end
end
