require "json"

module Migration
  class SampleImportService
    attr_reader :input_dir, :overwrite, :dry_run

    def initialize(input_dir:, overwrite: false, dry_run: false)
      @input_dir = Pathname(input_dir)
      @overwrite = overwrite
      @dry_run = dry_run
    end

    def call
      payload_paths = Dir.glob(input_dir.join("datasets", "*.json").to_s).sort

      summary = {
        input_dir: input_dir.to_s,
        total_payloads: payload_paths.length,
        created: 0,
        updated: 0,
        skipped_existing: 0,
        would_create: 0,
        would_update: 0,
        failed: 0,
        records: []
      }

      payload_paths.each do |path|
        payload = JSON.parse(File.read(path))
        result = DatasetUpsertService.new(
          payload: payload,
          overwrite: overwrite,
          dry_run: dry_run,
          require_sensitive_fields: false
        ).call

        increment_summary(summary, result.status)
        summary[:records] << {
          file: path,
          status: result.status,
          key: result.dataset_key,
          identifier: result.identifier,
          message: result.message
        }
      end

      File.write(input_dir.join("import_summary.json"), JSON.pretty_generate(summary))
      summary
    end

    private

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
