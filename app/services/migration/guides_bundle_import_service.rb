require "json"
require "digest"
require "set"

module Migration
  class GuidesBundleImportService
    attr_reader :bundle_path, :dry_run, :checksum_path, :manifest_path, :replace_all, :report_path

    VALID_TYPES = [ "Guide::Section", "Guide::Item", "Guide::Subitem" ].freeze

    def initialize(bundle_path:, dry_run: false, checksum_path: nil, manifest_path: nil, replace_all: true, report_path: nil)
      @bundle_path = Pathname(bundle_path)
      @dry_run = dry_run
      @checksum_path = checksum_path.present? ? Pathname(checksum_path) : nil
      @manifest_path = manifest_path.present? ? Pathname(manifest_path) : nil
      @replace_all = replace_all
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
      verify_hierarchy!(payloads)

      if dry_run
        summary[:would_create] = payloads.size
        summary[:processed_count] = payloads.size
        summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_count") }
        summary[:checksum] = safe_expected_checksum
        write_report_artifact!(summary)
        return summary
      end

      ActiveRecord::Base.transaction do
        clear_existing_guides! if replace_all

        payloads.each_with_index do |payload, idx|
          import_payload!(payload)
          summary[:created] += 1
          summary[:records] << { line: idx + 1, status: :created, type: payload.fetch("type"), id: payload.fetch("attributes").fetch("id") }
        end

        reset_guide_sequences!
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

        unless VALID_TYPES.include?(type)
          raise ArgumentError, "unsupported guide record type at line #{line_number}: #{type}"
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

      actual = payloads.each_with_object(Hash.new(0)) { |payload, counts| counts[payload["type"]] += 1 }
      expected = manifest_data["counts"].transform_values(&:to_i)

      [ "Guide::Section", "Guide::Item", "Guide::Subitem" ].each do |type|
        next if expected[type].to_i == actual[type].to_i

        raise ArgumentError, "manifest count mismatch for #{type}"
      end
    end

    def verify_hierarchy!(payloads)
      section_ids = payloads.filter { |p| p["type"] == "Guide::Section" }.map { |p| p["attributes"]["id"].to_i }.to_set
      item_records = payloads.filter { |p| p["type"] == "Guide::Item" }
      item_ids = item_records.map { |p| p["attributes"]["id"].to_i }.to_set

      item_records.each do |item|
        section_id = item.fetch("attributes").fetch("section_id", nil)
        raise ArgumentError, "item missing section_id for id=#{item.dig("attributes", "id")}" if section_id.blank?
        raise ArgumentError, "item references unknown section_id=#{section_id}" unless section_ids.include?(section_id.to_i)
      end

      payloads.filter { |p| p["type"] == "Guide::Subitem" }.each do |subitem|
        item_id = subitem.fetch("attributes").fetch("item_id", nil)
        raise ArgumentError, "subitem missing item_id for id=#{subitem.dig("attributes", "id")}" if item_id.blank?
        raise ArgumentError, "subitem references unknown item_id=#{item_id}" unless item_ids.include?(item_id.to_i)
      end
    end

    def import_payload!(payload)
      type = payload.fetch("type")
      attrs = payload.fetch("attributes").dup
      body = attrs.delete("body")

      case type
      when "Guide::Section"
        import_section!(attrs, body)
      when "Guide::Item"
        import_item!(attrs, body)
      when "Guide::Subitem"
        import_subitem!(attrs, body)
      else
        raise ArgumentError, "unsupported type: #{type}"
      end
    end

    def import_section!(attrs, body)
      record = Guide::Section.create!(
        id: attrs["id"],
        anchor: attrs["anchor"],
        label: attrs["label"],
        ordinal: attrs["ordinal"],
        public: attrs["public"],
        heading: attrs["heading"],
        created_at: parse_time(attrs["created_at"]),
        updated_at: parse_time(attrs["updated_at"])
      )
      assign_body!(record, body)
    end

    def import_item!(attrs, body)
      record = Guide::Item.create!(
        id: attrs["id"],
        section_id: attrs["section_id"],
        anchor: attrs["anchor"],
        label: attrs["label"],
        ordinal: attrs["ordinal"],
        public: attrs["public"],
        heading: attrs["heading"],
        created_at: parse_time(attrs["created_at"]),
        updated_at: parse_time(attrs["updated_at"])
      )
      assign_body!(record, body)
    end

    def import_subitem!(attrs, body)
      record = Guide::Subitem.create!(
        id: attrs["id"],
        item_id: attrs["item_id"],
        anchor: attrs["anchor"],
        label: attrs["label"],
        ordinal: attrs["ordinal"],
        public: attrs["public"],
        heading: attrs["heading"],
        created_at: parse_time(attrs["created_at"]),
        updated_at: parse_time(attrs["updated_at"])
      )
      assign_body!(record, body)
    end

    def assign_body!(record, body)
      return if body.blank?

      record.body = Migration::GuidesHtmlSanitizer.sanitize_html(body)
      record.save!
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def clear_existing_guides!
      ActionText::RichText.where(record_type: VALID_TYPES, name: "body").delete_all
      Guide::Subitem.delete_all
      Guide::Item.delete_all
      Guide::Section.delete_all
    end

    def reset_guide_sequences!
      connection = ActiveRecord::Base.connection
      connection.reset_pk_sequence!(Guide::Section.table_name)
      connection.reset_pk_sequence!(Guide::Item.table_name)
      connection.reset_pk_sequence!(Guide::Subitem.table_name)
    end

    def manifest_data
      return @manifest_data if defined?(@manifest_data)

      @manifest_data = manifest_path ? JSON.parse(File.read(manifest_path)) : nil
      if @manifest_data && @manifest_data["format_version"].present? && @manifest_data["format_version"].to_i != 1
        raise ArgumentError, "unsupported guides bundle format_version"
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
          import_type: "guides_bundle",
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
  end
end
