require "json"

# Orchestrates full cutover import sequence from legacy databank exports.
# Expected directory structure created by migration:legacy:export_all with SEPARATE_NESTED_ITEMS_BUNDLE=true:
#   /tmp/databank_exports/
#   ├── users_20260618T220000Z/                      (migration:legacy:export_users_bundle)
#   ├── dataset_flat_20260605T212924Z/               (migration:legacy:export_bundle - structure only)
#   │   └── legacy_datasets.ndjson                   (datasets + datafiles, NO nested items)
#   ├── dataset_nested_items_20260605T212924Z/       (migration:legacy:export_nested_items_bundle)
#   │   └── legacy_nested_items.ndjson               (nested items only)
#   ├── permissions_20260605T213042Z/
#   ├── dataset_access_grants_20260605T213119Z/
#   ├── guide_20260605T213946Z/
#   ├── spotlight_20260605T214012Z/
#   ├── medusa_ingests_20260605T214056Z/
#   ├── download_metrics_20260605T214133Z/
#   └── audit_20260618T221000Z/
#
# Recommended import command (matches the export command structure):
#   After exporting with: RAILS_ENV=demo SEPARATE_NESTED_ITEMS_BUNDLE=true bin/rails migration:legacy:export_all OUTPUT_ROOT=/tmp/databank_exports
#   Import with:         BUNDLE_ROOT=/tmp/databank_exports SEPARATE_NESTED_ITEMS_IMPORT=true CHUNKED_DATASET_IMPORT=true bundle exec rails cutover:import_all
#
# This two-phase protocol:
#   - Phase 1: Imports all users, then dataset structure (datasets + datafiles only)
#   - Phase 2: Imports nested items separately
#   - Phase 3: Imports all remaining bundles (permissions, grants, guides, spotlights, medusa, metrics, audits)
#   - Allows resumable chunked import windows for large datasets
#   - Memory-efficient for very large nested_items imports
#
# Other import options:
#
# For dry-run (no database changes):
#   BUNDLE_ROOT=/tmp/databank_exports SEPARATE_NESTED_ITEMS_IMPORT=true CHUNKED_DATASET_IMPORT=true DRY_RUN=true bundle exec rails cutover:import_all
#
# For simpler single-phase import (all data in one pass, less resumable):
#   BUNDLE_ROOT=/tmp/databank_exports bundle exec rails cutover:import_all
#   (Only use if export was WITHOUT SEPARATE_NESTED_ITEMS_BUNDLE=true)
#
# Runbook (typical demo scenario using two-phase import):
#   Preconditions:
#     - Export completed: RAILS_ENV=demo SEPARATE_NESTED_ITEMS_BUNDLE=true bin/rails migration:legacy:export_all OUTPUT_ROOT=/tmp/databank_exports
#     - Fresh databank-2 deploy ready
#     - Checkpoint files cleared: script/clear_import_checkpoints.sh /tmp/databank_exports
#
#   Steps:
#     1) Full chunked import (all bundles, two-phase dataset handling, resumable):
#        RAILS_ENV=demo BUNDLE_ROOT=/tmp/databank_exports SEPARATE_NESTED_ITEMS_IMPORT=true CHUNKED_DATASET_IMPORT=true bundle exec rails cutover:import_all
#     2) Verify outcomes:
#        RAILS_ENV=demo bundle exec rails cutover:reconcile
#        RAILS_ENV=demo bundle exec rails cutover:smoke ALLOW_ISSUES=true
#
#   Detached (SSH-safe with line-buffered logs, recommended for remote/long-running):
#     cd /home/databank/current && nohup stdbuf -oL -eL env \
#       RAILS_ENV=demo \
#       BUNDLE_ROOT=/tmp/databank_exports \
#       SEPARATE_NESTED_ITEMS_IMPORT=true \
#       CHUNKED_DATASET_IMPORT=true \
#       bundle exec rails cutover:import_all \
#       > /tmp/cutover_import_all.log 2>&1 < /dev/null &
#     tail -n 100 -F /tmp/cutover_import_all.log
#     (Use this for SSH sessions; survives connection drops and shows real-time progress)
#
# For large individual dataset chunk imports (resume capability over SSH):
#   cd /home/databank/current && nohup stdbuf -oL -eL env \
#     RAILS_ENV=demo \
#     DIR=/tmp/databank_exports/dataset_flat_<timestamp> \
#     BUNDLE_FILE=legacy_datasets.ndjson \
#     CHECKPOINT_FILE=flat_bundle_structure_import.checkpoint.json \
#     REPORT_FILE=cutover_datasets_report.json \
#     FLAT_BUNDLE_IMPORT_DIAGNOSTIC_LOGGING=true \
#     FLAT_BUNDLE_IMPORT_BATCH_SIZE=25 \
#     MAX_RECORDS=10000 \
#     bundle exec rails migration:flat_bundle:import_structure_in_chunks \
#     > /tmp/flat_bundle_structure_import.log 2>&1 < /dev/null &
#   tail -n 100 -F /tmp/flat_bundle_structure_import.log
#
# Before a fresh import run, clear checkpoint and lock files left by previous runs:
#   script/clear_import_checkpoints.sh /tmp/databank_exports
#
# This removes the following files from every subdirectory of BUNDLE_ROOT:
#   flat_bundle_import.checkpoint.json
#   flat_bundle_structure_import.checkpoint.json
#   flat_bundle_nested_items_import.checkpoint.json
#   flat_bundle_import.lock
#
# Without clearing these, chunked importers will resume from the last checkpoint
# rather than starting fresh.
#


namespace :cutover do
  # dir_prefix matches the subdir prefix created by the legacy export tasks, e.g.:
  #   migration:legacy:export_bundle           → dataset_flat_<timestamp>/
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
      dir_prefixes: [ "dataset_flat_", "dataset_" ]
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

  CUTOVER_NESTED_ITEMS_STEP = {
    key: "nested_items",
    task: "migration:flat_bundle:import_nested_items_from_dir",
    default_bundle_file: "legacy_nested_items.ndjson",
    dir_env: "NESTED_ITEMS_DIR",
    dir_prefixes: [ "dataset_nested_items_", "dataset_flat_", "dataset_" ]
  }.freeze

  CUTOVER_REQUIRED_RUN_TYPES_DEFAULT = %w[
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

  CUTOVER_REQUIRED_RUN_TYPES_TWO_PHASE = %w[
    users_bundle_import
    flat_bundle_structure_import
    flat_bundle_nested_items_import
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
  def resolve_step_dir(step, bundle_root, bundle_file: nil)
    explicit = ENV[step[:dir_env]].presence
    return explicit if explicit.present?
    return bundle_root unless bundle_root.present?

    prefixes = Array(step[:dir_prefixes]).presence || Array(step[:dir_prefix]).presence
    return bundle_root if prefixes.blank?

    candidates = prefixes.flat_map do |prefix|
      Dir.glob(File.join(bundle_root, "#{prefix}[0-9]*"))
    end
                       .select { |path| File.directory?(path) }
                       .uniq
                       .sort_by { |path| File.mtime(path) }
                       .reverse

    if candidates.empty?
      prefix_description = prefixes.map { |prefix| "'#{prefix}*'" }.join(" or ")
      raise ArgumentError, "no subdirectory matching #{prefix_description} found in #{bundle_root}"
    end

    if bundle_file.present?
      bundle_candidates = candidates.select do |path|
        File.exist?(File.join(path, bundle_file))
      end
      return bundle_candidates.first if bundle_candidates.any?
    end

    candidates.first
  end

  def chunked_dataset_import?
    ENV.fetch("CHUNKED_DATASET_IMPORT", "false").casecmp("true").zero?
  end

  def chunked_download_metrics_import?
    ENV.fetch("CHUNKED_DOWNLOAD_METRICS_IMPORT", "false").casecmp("true").zero?
  end

  def separate_nested_items_import?
    ENV.fetch("SEPARATE_NESTED_ITEMS_IMPORT", "false").casecmp("true").zero?
  end

  def cutover_required_run_types
    separate_nested_items_import? ? CUTOVER_REQUIRED_RUN_TYPES_TWO_PHASE : CUTOVER_REQUIRED_RUN_TYPES_DEFAULT
  end

  def cutover_import_steps
    steps = CUTOVER_IMPORT_STEPS.dup
    return steps unless separate_nested_items_import?

    dataset_index = steps.index { |step| step[:key] == "datasets" }
    return steps << CUTOVER_NESTED_ITEMS_STEP if dataset_index.nil?

    steps.insert(dataset_index + 1, CUTOVER_NESTED_ITEMS_STEP)
  end

  def skipped_cutover_step_keys
    raw = ENV["SKIP_STEPS"].to_s
    return [] if raw.blank?

    raw.split(",").map { |value| value.to_s.strip.downcase }.reject(&:blank?)
  end

  def step_task_name(step)
    if step[:key] == "datasets"
      return "migration:flat_bundle:import_structure_in_chunks" if separate_nested_items_import? && chunked_dataset_import?
      return "migration:flat_bundle:import_structure_from_dir" if separate_nested_items_import?
      return "migration:flat_bundle:import_in_chunks" if chunked_dataset_import?
    end

    if step[:key] == "download_metrics"
      return "migration:download_metrics:import_in_chunks" if chunked_download_metrics_import?
    end

    if step[:key] == "nested_items"
      return "migration:flat_bundle:import_nested_items_in_chunks" if chunked_dataset_import?
    end

    step[:task]
  end

  desc "Run all cutover bundle imports in required order (fails fast)"
  task import_all: :environment do
    bundle_root = ENV["BUNDLE_ROOT"].presence
    dry_run_enabled = ENV.fetch("DRY_RUN", "false").casecmp("true").zero?
    skipped_steps = skipped_cutover_step_keys

    if skipped_steps.any?
      puts "Skipping cutover steps: #{skipped_steps.join(', ')}"
    end

    cutover_import_steps.each do |step|
      next if skipped_steps.include?(step[:key])

      bundle_file = ENV["#{step[:key].upcase}_BUNDLE_FILE"].presence || step[:default_bundle_file]
      step_dir = resolve_step_dir(step, bundle_root, bundle_file: bundle_file)
      raise ArgumentError, "missing #{step[:dir_env]} or BUNDLE_ROOT for #{step[:key]}" if step_dir.blank?

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

      task_name = step_task_name(step)
      puts "Running #{task_name} DIR=#{step_dir} BUNDLE_FILE=#{bundle_file}"
      if step[:key] == "datasets" && !chunked_dataset_import?
        puts "Tip: set CHUNKED_DATASET_IMPORT=true for resumable dataset import windows on large bundles"
      end
      if step[:key] == "datasets" && !separate_nested_items_import?
        puts "Tip: set SEPARATE_NESTED_ITEMS_IMPORT=true to split structure and nested item pipelines"
      end
      if step[:key] == "download_metrics" && !chunked_download_metrics_import?
        puts "Tip: set CHUNKED_DOWNLOAD_METRICS_IMPORT=true for resumable download metrics imports on large bundles"
      end
      rake_task = Rake::Task[task_name]
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

    cutover_required_run_types.each do |run_type|
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
      required_run_types: cutover_required_run_types,
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

    cutover_required_run_types.each do |run_type|
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
