require "json"
require "digest"

module Migration
  class AuditsBundleImportService
    attr_reader :bundle_path, :dry_run, :checksum_path, :manifest_path, :report_path

    def initialize(bundle_path:, dry_run: false, checksum_path: nil, manifest_path: nil, report_path: nil)
      @bundle_path = Pathname(bundle_path)
      @dry_run = dry_run
      @checksum_path = checksum_path.present? ? Pathname(checksum_path) : nil
      @manifest_path = manifest_path.present? ? Pathname(manifest_path) : nil
      @report_path = resolve_report_path(report_path)
      @identity_cache = {}
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

      payloads = parse_payloads(summary: summary)
      verify_expected_record_count!(processed_count: payloads.size)
      verify_manifest_counts!(payloads: payloads)

      if dry_run
        summary[:would_create] = payloads.size
        summary[:processed_count] = payloads.size
        summary[:expected_record_count] = safe_manifest_value { manifest_data&.dig("record_count") }
        summary[:checksum] = safe_expected_checksum
        write_report_artifact!(summary)
        return summary
      end

      ActiveRecord::Base.transaction do
        payloads.each_with_index do |payload, index|
          import_payload!(payload: payload, line_number: index + 1, summary: summary)
        end
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
      return if secure_compare(left: actual, right: expected)

      raise ArgumentError, "bundle checksum mismatch"
    end

    def expected_checksum
      from_manifest = manifest_data["sha256"].to_s.strip if manifest_data
      return from_manifest if from_manifest.present?

      return nil unless checksum_path

      token = File.read(checksum_path).strip.split.first
      token&.strip
    end

    def parse_payloads(summary:)
      payloads = []

      File.foreach(bundle_path).with_index(1) do |line, line_number|
        next if line.strip.empty?

        payload = JSON.parse(line)
        unless payload["type"].to_s == "Audit"
          raise ArgumentError, "unsupported audit record type at line #{line_number}: #{payload['type']}"
        end

        unless payload["attributes"].is_a?(Hash)
          raise ArgumentError, "missing attributes hash at line #{line_number}"
        end

        payloads << payload
      rescue JSON::ParserError => e
        summary[:records] << { line: line_number, status: :failed, message: "invalid JSON: #{e.message}" }
        raise ArgumentError, "invalid JSON at line #{line_number}"
      end

      payloads
    end

    def verify_expected_record_count!(processed_count:)
      return unless manifest_data && manifest_data["record_count"].present?

      expected = manifest_data["record_count"].to_i
      return if expected == processed_count

      raise ArgumentError, "bundle record count mismatch"
    end

    def verify_manifest_counts!(payloads:)
      return unless manifest_data && manifest_data["counts"].is_a?(Hash)

      expected = manifest_data["counts"]["Audit"]
      return if expected.nil? || expected.to_i == payloads.size

      raise ArgumentError, "manifest count mismatch for Audit"
    end

    def import_payload!(payload:, line_number:, summary:)
      attributes = payload.fetch("attributes")
      dataset_key = attributes["dataset_key"].to_s.strip
      raise ArgumentError, "missing dataset_key at line #{line_number}" if dataset_key.blank?

      dataset = Dataset.find_by(key: dataset_key)
      raise ArgumentError, "dataset not found for audit line #{line_number}: #{dataset_key}" if dataset.nil?

      auditable_reference = attributes["auditable"] || {}
      associated_reference = attributes["associated"] || {}

      auditable_type = auditable_reference["type"].to_s.presence
      auditable_id = resolve_reference_id(dataset: dataset, reference: auditable_reference)
      associated_type = associated_reference["type"].to_s.presence
      associated_id = resolve_reference_id(dataset: dataset, reference: associated_reference)

      user_id = resolve_user_id(attributes: attributes)

      audit_attributes = {
        auditable_type: auditable_type,
        auditable_id: auditable_id,
        associated_type: associated_type,
        associated_id: associated_id,
        user_id: user_id,
        user_type: attributes["user_type"].to_s.presence,
        username: attributes["username"].to_s.presence,
        action: attributes["action"].to_s,
        audited_changes: normalized_audited_changes(attributes["audited_changes"]),
        version: attributes["version"],
        comment: attributes["comment"],
        remote_address: attributes["remote_address"],
        request_uuid: attributes["request_uuid"],
        created_at: parse_time(attributes["created_at"])
      }

      existing = Audited::Audit.find_by(
        auditable_type: audit_attributes[:auditable_type],
        auditable_id: audit_attributes[:auditable_id],
        associated_type: audit_attributes[:associated_type],
        associated_id: audit_attributes[:associated_id],
        action: audit_attributes[:action],
        version: audit_attributes[:version],
        created_at: audit_attributes[:created_at],
        request_uuid: audit_attributes[:request_uuid]
      )

      if existing
        summary[:skipped_existing] += 1
        summary[:records] << { line: line_number, status: :skipped_existing, dataset_key: dataset_key, legacy_audit_id: attributes["legacy_audit_id"] }
        return
      end

      Audited::Audit.create!(audit_attributes)
      summary[:created] += 1
      summary[:records] << { line: line_number, status: :created, dataset_key: dataset_key, legacy_audit_id: attributes["legacy_audit_id"] }
    end

    def resolve_user_id(attributes:)
      identity = attributes["user_identity"]
      return nil unless identity.is_a?(Hash)

      provider = identity["provider"].to_s.strip.presence
      uid = identity["uid"].to_s.strip.presence
      email = identity["email"].to_s.strip.downcase.presence

      user = User.find_by(provider: provider, uid: uid) if provider && uid
      user ||= User.find_by(email: email) if email
      user&.id
    end

    def normalized_audited_changes(value)
      value.is_a?(Hash) ? value : {}
    end

    def resolve_reference_id(dataset:, reference:)
      return nil unless reference.is_a?(Hash)

      type = reference["type"].to_s
      return nil if type.blank?

      signature = identity_signature(dataset_key: dataset.key, reference: reference)
      return @identity_cache[signature] if @identity_cache.key?(signature)

      resolved_id = find_live_record_id(dataset: dataset, type: type, locator: reference["locator"] || {})
      resolved_id ||= synthetic_id_for(signature: signature)
      @identity_cache[signature] = resolved_id
    end

    def identity_signature(dataset_key:, reference:)
      payload = {
        dataset_key: dataset_key,
        type: reference["type"].to_s,
        legacy_id: reference["legacy_id"],
        locator: normalized_hash(reference["locator"] || {})
      }

      JSON.generate(payload)
    end

    def find_live_record_id(dataset:, type:, locator:)
      case type
      when "Dataset"
        dataset.id
      when "Creator"
        find_creator(dataset: dataset, locator: locator)&.id
      when "Contributor"
        find_contributor(dataset: dataset, locator: locator)&.id
      when "Funder"
        find_funder(dataset: dataset, locator: locator)&.id
      when "RelatedMaterial"
        find_related_material(dataset: dataset, locator: locator)&.id
      end
    end

    def find_creator(dataset:, locator:)
      dataset.creators.detect { |record| person_record_matches?(record: record, locator: locator) }
    end

    def find_contributor(dataset:, locator:)
      dataset.contributors.detect { |record| person_record_matches?(record: record, locator: locator) }
    end

    def person_record_matches?(record:, locator:)
      desired_position = locator["row_position"] || locator[:row_position]
      if desired_position.present?
        return false unless [ record.row_position, record.position ].compact.map(&:to_i).include?(desired_position.to_i)
      end

      desired_given_name = locator["given_name"] || locator[:given_name]
      return false if desired_given_name.present? && record.given_name.to_s != desired_given_name.to_s

      desired_family_name = locator["family_name"] || locator[:family_name]
      return false if desired_family_name.present? && record.family_name.to_s != desired_family_name.to_s

      desired_name = locator["institution_name"] || locator[:institution_name] || locator["name"] || locator[:name]
      if desired_name.present?
        candidate_names = [ record.institution_name, record.name ]
        candidate_names << record.display_name if record.respond_to?(:display_name)
        return false unless candidate_names.compact.map(&:to_s).include?(desired_name.to_s)
      end

      desired_position.present? || desired_given_name.present? || desired_family_name.present? || desired_name.present?
    end

    def find_funder(dataset:, locator:)
      dataset.funders.detect do |record|
        fields_match?(record.name, locator["name"] || locator[:name]) &&
          fields_match?(record.identifier, locator["identifier"] || locator[:identifier]) &&
          fields_match?(record.grant, locator["grant"] || locator[:grant])
      end
    end

    def find_related_material(dataset:, locator:)
      dataset.related_materials.detect do |record|
        next false unless fields_match?(record.uri, locator["uri"] || locator[:uri])
        next false unless fields_match?(record.citation, locator["citation"] || locator[:citation])
        next false unless fields_match?(record.link, locator["link"] || locator[:link])
        next false unless fields_match?(record.material_type, locator["material_type"] || locator[:material_type])

        desired_title = locator["title"] || locator[:title]
        fields_match?(record.title, desired_title)
      end
    end

    def fields_match?(actual, expected)
      return true if expected.blank?

      actual.to_s == expected.to_s
    end

    def synthetic_id_for(signature:)
      token = Digest::SHA256.hexdigest(signature)[0, 12].to_i(16)
      -((token % 2_000_000_000) + 1)
    end

    def normalized_hash(hash)
      hash.to_h.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_s] = value.is_a?(Hash) ? normalized_hash(value) : value
      end.sort.to_h
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def manifest_data
      @manifest_data ||= manifest_path ? JSON.parse(File.read(manifest_path)) : nil
    end

    def resolve_report_path(report_path)
      path = report_path.presence || bundle_path.dirname.join("import_report.json").to_s
      path = Pathname(path)
      path.absolute? ? path : bundle_path.dirname.join(path)
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

    def write_report_artifact!(summary)
      Migration::RunReportWriter.new(
        report_path: report_path,
        report: {
          generated_at: Time.current.utc.iso8601,
          import_type: "audits_bundle",
          bundle_path: bundle_path.to_s,
          checksum_path: checksum_path&.to_s,
          manifest_path: manifest_path&.to_s,
          summary: summary
        }
      ).call
    end

    def secure_compare(left:, right:)
      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
