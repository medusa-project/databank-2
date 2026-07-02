require "json"

# Orchestrates full cutover import sequence from legacy databank exports.
# Expected directory structure from migration:legacy:export_all:
#   /tmp/databank_exports/
#   ├── users_20260618T220000Z/                 (migration:legacy:export_users_bundle)
#   ├── dataset_20260605T212924Z/               (migration:legacy:export_bundle - flat NDJSON format)
#   ├── permissions_20260605T213042Z/           (migration:legacy:export_permissions_bundle)
#   ├── dataset_access_grants_20260605T213119Z/ (migration:legacy:export_dataset_access_grants_bundle)
#   ├── guide_20260605T213946Z/                 (migration:legacy:export_guides_bundle)
#   ├── spotlight_20260605T214012Z/             (migration:legacy:export_featured_researchers_bundle)
#   ├── medusa_ingests_20260605T214056Z/        (migration:legacy:export_medusa_ingests_bundle)
#   ├── download_metrics_20260605T214133Z/      (migration:legacy:export_download_metrics_bundle)
#   └── audit_20260618T221000Z/                 (migration:legacy:export_audits_bundle)
#
# Dataset imports use flat NDJSON format (format_version: 2):
#   - Separate records for datasets, datafiles, nested_items
#   - Streaming batch import (100 records per flush)
#   - Memory-efficient for large exports
#
# To run the full cutover import:
#   BUNDLE_ROOT=/tmp/databank_exports bundle exec rails cutover:import_all
#
# To run with dry-run (no database changes):
#   BUNDLE_ROOT=/tmp/databank_exports DRY_RUN=true bundle exec rails cutover:import_all


namespace :cutover do
  # dir_prefix matches the subdir prefix created by the legacy export tasks, e.g.:
  #   migration:legacy:export_bundle           → dataset_<timestamp>/
  #   migration:legacy:export_permissions_bundle → permissions_<timestamp>/
  CUTOVER_IMPORT_STEPS = [
    {
      key: "users",
      task: "migration:users:import_from_dir",
      default_bundle_file: "legacy_users.ndjson",
      dir_env: "USERS_DIR",
      dir_prefix: "users_"
    },
    {
      key: "datasets",
      task: "migration:flat_bundle:import_from_dir",
      default_bundle_file: "legacy_datasets.ndjson",
      dir_env: "DATASETS_DIR",
      dir_prefix: "dataset_"
    },
    {
      key: "permissions",
      task: "migration:permissions:import_from_dir",
      default_bundle_file: "legacy_permissions.ndjson",
      dir_env: "PERMISSIONS_DIR",
      dir_prefix: "permissions_"
    },
    {
      key: "dataset_access_grants",
      task: "migration:dataset_access_grants:import_from_dir",
      default_bundle_file: "legacy_dataset_access_grants.ndjson",
      dir_env: "DATASET_ACCESS_GRANTS_DIR",
      dir_prefix: "dataset_access_grants_"
    },
    {
      key: "guides",
      task: "migration:guides:import_from_dir",
      default_bundle_file: "legacy_guides.ndjson",
      dir_env: "GUIDES_DIR",
      dir_prefix: "guide_"
    },
    {
      key: "spotlights",
      task: "migration:spotlights:import_from_dir",
      default_bundle_file: "legacy_featured_researchers.ndjson",
      dir_env: "SPOTLIGHTS_DIR",
      dir_prefix: "spotlight_"
    },
    {
      key: "medusa_ingests",
      task: "migration:medusa_ingests:import_from_dir",
      default_bundle_file: "legacy_medusa_ingests.ndjson",
      dir_env: "MEDUSA_INGESTS_DIR",
      dir_prefix: "medusa_ingests_"
    },
    {
      key: "download_metrics",
      task: "migration:download_metrics:import_from_dir",
      default_bundle_file: "legacy_download_metrics.ndjson",
      dir_env: "DOWNLOAD_METRICS_DIR",
      dir_prefix: "download_metrics_"
    },
    {
      key: "audits",
      task: "migration:audits:import_from_dir",
      default_bundle_file: "legacy_audits.ndjson",
      dir_env: "AUDITS_DIR",
      dir_prefix: "audit_"
    }
  ].freeze

  CUTOVER_REQUIRED_RUN_TYPES = %w[
    users_bundle_import
    flat_bundle_import
    permissions_bundle_import
    dataset_access_grants_bundle_import
    guides_bundle_import
    featured_researchers_bundle_import
    medusa_ingests_bundle_import
    download_metrics_bundle_import
    audits_bundle_import
  ].freeze

  def cutover_report_path(prefix)
    report_override = ENV["REPORT_FILE"].presence
    return Pathname(report_override) if report_override.present? && Pathname(report_override).absolute?
    return Rails.root.join(report_override) if report_override.present?

    Rails.root.join("tmp", "#{prefix}_#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.json")
  end

  def latest_run_for(run_type)
    MigrationRun.where(run_type: run_type).order(started_at: :desc, id: :desc).first
  end

  # When BUNDLE_ROOT is used (no per-step DIR override), find the most recently
  # modified subdirectory matching the step's dir_prefix within bundle_root.
  # This matches the timestamped subdir layout created by legacy export tasks.
  def resolve_step_dir(step, bundle_root)
    explicit = ENV[step[:dir_env]].presence
    return explicit if explicit.present?
    return bundle_root unless bundle_root.present? && step[:dir_prefix].present?

    candidates = Dir.glob(File.join(bundle_root, "#{step[:dir_prefix]}[0-9]*"))
                    .select { |path| File.directory?(path) }
                    .sort_by { |path| File.mtime(path) }
                    .reverse

    raise ArgumentError, "no subdirectory matching '#{step[:dir_prefix]}*' found in #{bundle_root}" if candidates.empty?

    candidates.first
  end

  desc "Run all cutover bundle imports in required order (fails fast)"
  task import_all: :environment do
    bundle_root = ENV["BUNDLE_ROOT"].presence
    dry_run_enabled = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?

    CUTOVER_IMPORT_STEPS.each do |step|
      step_dir = resolve_step_dir(step, bundle_root)
      raise ArgumentError, "missing #{step[:dir_env]} or BUNDLE_ROOT for #{step[:key]}" if step_dir.blank?

      bundle_file = ENV["#{step[:key].upcase}_BUNDLE_FILE"].presence || step[:default_bundle_file]
      report_file = ENV["#{step[:key].upcase}_REPORT_FILE"].presence || "cutover_#{step[:key]}_report.json"

      old_env = {
        "DIR" => ENV["DIR"],
        "BUNDLE_FILE" => ENV["BUNDLE_FILE"],
        "REPORT_FILE" => ENV["REPORT_FILE"],
        "DRY_RUN" => ENV["DRY_RUN"]
      }

      ENV["DIR"] = step_dir
      ENV["BUNDLE_FILE"] = bundle_file
      ENV["REPORT_FILE"] = report_file
      if dry_run_enabled
        ENV["DRY_RUN"] = "true"
      else
        ENV.delete("DRY_RUN")
      end

      puts "Running #{step[:task]} DIR=#{step_dir} BUNDLE_FILE=#{bundle_file}"
      rake_task = Rake::Task[step[:task]]
      rake_task.reenable
      rake_task.invoke
    ensure
      old_env&.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
    end

    puts "Cutover import sequence complete."
  end

  desc "Summarize cutover migration outcomes from MigrationRun in one JSON report"
  task reconcile: :environment do
    report_path = cutover_report_path("cutover_reconciliation")
    issues = []
    runs = {}

    CUTOVER_REQUIRED_RUN_TYPES.each do |run_type|
      run = latest_run_for(run_type)
      if run.nil?
        issues << "missing migration run for #{run_type}"
        next
      end

      runs[run_type] = {
        id: run.id,
        status: run.status,
        started_at: run.started_at,
        completed_at: run.completed_at,
        created_count: run.created_count,
        updated_count: run.updated_count,
        skipped_count: run.skipped_count,
        failed_count: run.failed_count,
        processed_count: run.processed_count,
        expected_count: run.expected_count,
        validation_error: run.validation_error,
        bundle_path: run.bundle_path,
        report_path: run.details["report_path"]
      }

      issues << "run #{run_type} has status=#{run.status}" unless run.status == "completed"
      issues << "run #{run_type} has failed_count=#{run.failed_count}" if run.failed_count.to_i.positive?
      issues << "run #{run_type} has validation_error=#{run.validation_error}" if run.validation_error.present?
    end

    output = {
      generated_at: Time.current.utc.iso8601,
      required_run_types: CUTOVER_REQUIRED_RUN_TYPES,
      issues: issues,
      runs: runs
    }

    FileUtils.mkdir_p(report_path.dirname)
    File.write(report_path, JSON.pretty_generate(output))

    puts "Reconciliation report: #{report_path}"
    puts "Issues: #{issues.count}"

    allow_issues = ENV.fetch("ALLOW_ISSUES", "false").casecmp("true").zero?
    raise "cutover reconciliation found issues" if issues.any? && !allow_issues
  end

  desc "Run post-import cutover smoke checks and emit one JSON report"
  task smoke: :environment do
    report_path = cutover_report_path("cutover_smoke")
    issues = []
    runs = {}
    allow_issues = ENV.fetch("ALLOW_ISSUES", "false").casecmp("true").zero?

    CUTOVER_REQUIRED_RUN_TYPES.each do |run_type|
      run = latest_run_for(run_type)
      if run.nil?
        issues << "missing migration run for #{run_type}"
        next
      end

      runs[run_type] = {
        id: run.id,
        status: run.status,
        failed_count: run.failed_count,
        validation_error: run.validation_error
      }

      issues << "run #{run_type} not completed" unless run.status == "completed"
      issues << "run #{run_type} has failed_count=#{run.failed_count}" if run.failed_count.to_i.positive?
      issues << "run #{run_type} has validation_error=#{run.validation_error}" if run.validation_error.present?
    end

    dataset_count = Dataset.count
    issues << "no datasets found" if dataset_count.zero?

    duplicate_tokens = Token.group(:dataset_key).having("COUNT(*) > 1").count
    issues << "duplicate tokens found for #{duplicate_tokens.keys.join(', ')}" if duplicate_tokens.any?

    output = {
      generated_at: Time.current.utc.iso8601,
      issues: issues,
      runs: runs,
      checks: {
        dataset_count: dataset_count,
        duplicate_token_dataset_keys: duplicate_tokens.keys
      }
    }

    FileUtils.mkdir_p(report_path.dirname)
    File.write(report_path, JSON.pretty_generate(output))

    puts "Smoke report: #{report_path}"
    puts "Issues: #{issues.count}"

    raise "cutover smoke failed" if issues.any? && !allow_issues
  end
end
