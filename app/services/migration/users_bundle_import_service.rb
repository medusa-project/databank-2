require "json"
require "digest"

module Migration
  class UsersBundleImportService
    attr_reader :bundle_path, :dry_run, :checksum_path, :manifest_path, :report_path

    ROLE_MAP = {
      "admin" => "curator",
      "depositor" => "depositor",
      "guest" => "guest",
      "no_deposit" => "no_deposit"
    }.freeze

    def initialize(bundle_path:, dry_run: false, checksum_path: nil, manifest_path: nil, report_path: nil)
      @bundle_path = Pathname(bundle_path)
      @dry_run = dry_run
      @checksum_path = checksum_path.present? ? Pathname(checksum_path) : nil
      @manifest_path = manifest_path.present? ? Pathname(manifest_path) : nil
      @report_path = resolve_report_path(report_path)
    end

    def call
      summary = initial_summary

      validate_paths!
      verify_bundle_integrity!

      payloads = parse_payloads(summary: summary)
      verify_expected_record_count!(processed_count: payloads.size)
      verify_manifest_counts!(payloads: payloads)

      payloads.each_with_index do |payload, index|
        import_payload!(payload: payload, line_number: index + 1, summary: summary)
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
      summary || initial_summary.merge(validation_error: e.message, failed: 1)
    end

    private

    def initial_summary
      {
        bundle_path: bundle_path.to_s,
        created: 0,
        updated: 0,
        skipped_existing: 0,
        would_create: 0,
        would_update: 0,
        failed: 0,
        skipped_unsupported_role: 0,
        skipped_invalid_identity: 0,
        skipped_ambiguous_match: 0,
        reconciled_by_email: 0,
        validation_error: nil,
        records: []
      }
    end

    def validate_paths!
      raise ArgumentError, "bundle not found: #{bundle_path}" unless bundle_path.file?
      raise ArgumentError, "checksum file not found: #{checksum_path}" if checksum_path && !checksum_path.file?
      raise ArgumentError, "manifest file not found: #{manifest_path}" if manifest_path && !manifest_path.file?
    end

    def verify_bundle_integrity!
      expected = expected_checksum
      return if expected.blank?

      actual = Digest::SHA256.file(bundle_path).hexdigest
      raise ArgumentError, "bundle checksum mismatch" unless secure_compare(left: actual, right: expected)
    end

    def expected_checksum
      from_manifest = manifest_data["sha256"].to_s.strip if manifest_data
      return from_manifest if from_manifest.present?
      return nil unless checksum_path

      File.read(checksum_path).strip.split.first.to_s.strip.presence
    end

    def parse_payloads(summary:)
      payloads = []

      File.foreach(bundle_path).with_index(1) do |line, line_number|
        next if line.strip.empty?

        payload = JSON.parse(line)
        raise ArgumentError, "unsupported user record type at line #{line_number}: #{payload['type']}" unless payload["type"].to_s == "User"
        raise ArgumentError, "missing attributes hash at line #{line_number}" unless payload["attributes"].is_a?(Hash)

        payloads << payload
      rescue JSON::ParserError => e
        summary[:records] << { line: line_number, status: :failed, message: "invalid JSON: #{e.message}" }
        raise ArgumentError, "invalid JSON at line #{line_number}"
      end

      payloads
    end

    def verify_expected_record_count!(processed_count:)
      return unless manifest_data && manifest_data["record_count"].present?
      raise ArgumentError, "bundle record count mismatch" unless manifest_data["record_count"].to_i == processed_count
    end

    def verify_manifest_counts!(payloads:)
      return unless manifest_data && manifest_data["counts"].is_a?(Hash)

      expected = manifest_data["counts"]["User"]
      return if expected.nil? || expected.to_i == payloads.size

      raise ArgumentError, "manifest count mismatch for User"
    end

    def import_payload!(payload:, line_number:, summary:)
      attributes = payload.fetch("attributes")
      provider = normalized_presence(attributes["provider"])
      uid = normalized_presence(attributes["uid"])
      email = normalized_email(attributes["email"])
      raw_role = normalized_presence(attributes["role"])
      mapped_role = normalized_mapped_role(raw_role: raw_role, mapped_role: attributes["mapped_role"])

      if mapped_role.blank?
        summary[:skipped_unsupported_role] += 1
        summary[:records] << { line: line_number, status: :skipped_unsupported_role, provider: provider, uid: uid, raw_role: raw_role }
        return
      end

      if provider.blank? || uid.blank? || email.blank?
        summary[:skipped_invalid_identity] += 1
        summary[:records] << { line: line_number, status: :skipped_invalid_identity, provider: provider, uid: uid, email: attributes["email"] }
        return
      end

      existing = User.find_by(provider: provider, uid: uid)
      matched_by_email = false

      if existing.nil?
        email_match = User.find_by(email: email)
        if email_match
          existing = email_match
          matched_by_email = true
        end
      end

      persisted_role = existing&.role == "admin" ? "admin" : mapped_role
      desired_attributes = {
        provider: provider,
        uid: uid,
        email: email,
        username: normalized_presence(attributes["username"]) || email.split("@").first,
        name: normalized_presence(attributes["name"]) || email,
        role: persisted_role
      }

      if dry_run
        status = existing.nil? ? :would_create : (attributes_differ?(record: existing, desired: desired_attributes) ? :would_update : :skipped_existing)
        summary[status] += 1 if summary.key?(status)
        summary[:reconciled_by_email] += 1 if matched_by_email && status != :skipped_existing
        summary[:records] << { line: line_number, status: status, provider: provider, uid: uid, email: email, mapped_role: mapped_role }
        return
      end

      if existing.nil?
        User.create!(desired_attributes)
        summary[:created] += 1
        summary[:records] << { line: line_number, status: :created, provider: provider, uid: uid, email: email, mapped_role: mapped_role }
        return
      end

      if attributes_differ?(record: existing, desired: desired_attributes)
        existing.update!(desired_attributes)
        summary[:updated] += 1
        summary[:reconciled_by_email] += 1 if matched_by_email
        summary[:records] << { line: line_number, status: :updated, provider: provider, uid: uid, email: email, mapped_role: mapped_role, reconciled_by_email: matched_by_email }
      else
        summary[:skipped_existing] += 1
        summary[:records] << { line: line_number, status: :skipped_existing, provider: provider, uid: uid, email: email }
      end
    end

    def attributes_differ?(record:, desired:)
      desired.any? { |key, value| record.public_send(key) != value }
    end

    def normalized_mapped_role(raw_role:, mapped_role:)
      normalized = normalized_presence(mapped_role)
      return normalized if User::ROLES.include?(normalized)

      ROLE_MAP[raw_role.to_s]
    end

    def normalized_presence(value)
      value.to_s.strip.presence
    end

    def normalized_email(value)
      raw = value.to_s.strip.downcase
      return nil if raw.blank?
      return nil unless raw =~ URI::MailTo::EMAIL_REGEXP

      raw
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
          import_type: "users_bundle",
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
