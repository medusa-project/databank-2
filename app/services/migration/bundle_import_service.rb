require "json"
require "digest"

module Migration
  class BundleImportService
    attr_reader :bundle_path, :overwrite, :dry_run, :checksum_path, :manifest_path

    def initialize(bundle_path:, overwrite: false, dry_run: false, checksum_path: nil, manifest_path: nil)
      @bundle_path = Pathname(bundle_path)
      @overwrite = overwrite
      @dry_run = dry_run
      @checksum_path = checksum_path.present? ? Pathname(checksum_path) : nil
      @manifest_path = manifest_path.present? ? Pathname(manifest_path) : nil
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

      processed_count = 0

      File.foreach(bundle_path).with_index(1) do |line, line_number|
        next if line.strip.empty?

        payload = JSON.parse(line)
        result = DatasetUpsertService.new(
          payload: payload,
          overwrite: overwrite,
          dry_run: dry_run,
          require_sensitive_fields: true
        ).call

        increment_summary(summary, result.status)
        summary[:records] << {
          line: line_number,
          status: result.status,
          key: result.dataset_key,
          identifier: result.identifier,
          message: result.message
        }
        processed_count += 1
      end

      verify_expected_record_count!(processed_count)

      summary
    rescue StandardError => e
      summary[:validation_error] = e.message if defined?(summary)
      summary[:failed] += 1 if defined?(summary)
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

      if checksum_path && !checksum_path.file?
        raise ArgumentError, "checksum file not found: #{checksum_path}"
      end

      if manifest_path && !manifest_path.file?
        raise ArgumentError, "manifest file not found: #{manifest_path}"
      end
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

    def verify_expected_record_count!(processed_count)
      return unless manifest_data && manifest_data["record_count"].present?

      expected = manifest_data["record_count"].to_i
      return if expected == processed_count

      raise ArgumentError, "bundle record count mismatch"
    end

    def manifest_data
      return @manifest_data if defined?(@manifest_data)

      @manifest_data = manifest_path ? JSON.parse(File.read(manifest_path)) : nil
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
