require "rails_helper"
require "rake"

RSpec.describe "cutover tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:import_all_task) { Rake::Task["cutover:import_all"] }
  let(:reconcile_task) { Rake::Task["cutover:reconcile"] }
  let(:smoke_task) { Rake::Task["cutover:smoke"] }

  before do
    import_all_task.reenable
    reconcile_task.reenable
    smoke_task.reenable
  end

  it "runs migration imports in required order using latest timestamped subdirs" do
    bundle_root = Rails.root.join("tmp", "cutover_orchestration")
    FileUtils.mkdir_p(bundle_root)

    # Create one timestamped subdir per step matching each dir_prefix.
    # CUTOVER_IMPORT_STEPS is a top-level constant defined inside the Rake namespace block.
    step_dirs = {}
    CUTOVER_IMPORT_STEPS.each do |step|
      prefixes = Array(step[:dir_prefixes]).presence || Array(step[:dir_prefix])
      subdir = bundle_root.join("#{prefixes.first}20260605T120000Z")
      FileUtils.mkdir_p(subdir)
      step_dirs[step[:key]] = subdir.to_s
    end

    expected_order = [
      "migration:users:import_from_dir",
      "migration:flat_bundle:import_from_dir",
      "migration:permissions:import_from_dir",
      "migration:dataset_access_grants:import_from_dir",
      "migration:guides:import_from_dir",
      "migration:spotlights:import_from_dir",
      "migration:medusa_ingests:import_from_dir",
      "migration:download_metrics:import_from_dir",
      "migration:audits:import_from_dir"
    ]

    invocations = []
    fake_tasks = {}

    expected_order.each do |task_name|
      task_double = instance_double(Rake::Task)
      allow(task_double).to receive(:reenable)
      allow(task_double).to receive(:invoke) do
        invocations << {
          task: task_name,
          dir: ENV["DIR"],
          bundle_file: ENV["BUNDLE_FILE"],
          dry_run: ENV["DRY_RUN"]
        }
      end
      fake_tasks[task_name] = task_double
    end

    allow(Rake::Task).to receive(:[]).and_wrap_original do |original, task_name|
      fake_tasks.fetch(task_name) { original.call(task_name) }
    end

    ENV["BUNDLE_ROOT"] = bundle_root.to_s
    ENV["DRY_RUN"] = "true"

    import_all_task.invoke

    expect(invocations.map { |call| call[:task] }).to eq(expected_order)
    # Each step's DIR should point into the correct timestamped subdir, not the root
    CUTOVER_IMPORT_STEPS.each_with_index do |step, index|
      expect(invocations[index][:dir]).to eq(step_dirs[step[:key]])
    end
    expect(invocations).to all(include(dry_run: "true"))
  ensure
    ENV.delete("BUNDLE_ROOT")
    ENV.delete("DRY_RUN")
    FileUtils.rm_rf(bundle_root)
  end

  it "uses chunked dataset import task when CHUNKED_DATASET_IMPORT is enabled" do
    bundle_root = Rails.root.join("tmp", "cutover_orchestration_chunked")
    FileUtils.mkdir_p(bundle_root)

    step_dirs = {}
    CUTOVER_IMPORT_STEPS.each do |step|
      prefixes = Array(step[:dir_prefixes]).presence || Array(step[:dir_prefix])
      subdir = bundle_root.join("#{prefixes.first}20260605T120000Z")
      FileUtils.mkdir_p(subdir)
      step_dirs[step[:key]] = subdir.to_s
    end

    expected_order = [
      "migration:users:import_from_dir",
      "migration:flat_bundle:import_in_chunks",
      "migration:permissions:import_from_dir",
      "migration:dataset_access_grants:import_from_dir",
      "migration:guides:import_from_dir",
      "migration:spotlights:import_from_dir",
      "migration:medusa_ingests:import_from_dir",
      "migration:download_metrics:import_from_dir",
      "migration:audits:import_from_dir"
    ]

    invocations = []
    fake_tasks = {}

    expected_order.each do |task_name|
      task_double = instance_double(Rake::Task)
      allow(task_double).to receive(:reenable)
      allow(task_double).to receive(:invoke) do
        invocations << {
          task: task_name,
          dir: ENV["DIR"],
          bundle_file: ENV["BUNDLE_FILE"],
          dry_run: ENV["DRY_RUN"]
        }
      end
      fake_tasks[task_name] = task_double
    end

    allow(Rake::Task).to receive(:[]).and_wrap_original do |original, task_name|
      fake_tasks.fetch(task_name) { original.call(task_name) }
    end

    ENV["BUNDLE_ROOT"] = bundle_root.to_s
    ENV["DRY_RUN"] = "true"
    ENV["CHUNKED_DATASET_IMPORT"] = "true"

    import_all_task.invoke

    expect(invocations.map { |call| call[:task] }).to eq(expected_order)
    CUTOVER_IMPORT_STEPS.each_with_index do |step, index|
      expect(invocations[index][:dir]).to eq(step_dirs[step[:key]])
    end
    expect(invocations).to all(include(dry_run: "true"))
  ensure
    ENV.delete("BUNDLE_ROOT")
    ENV.delete("DRY_RUN")
    ENV.delete("CHUNKED_DATASET_IMPORT")
    FileUtils.rm_rf(bundle_root)
  end

  it "skips requested cutover steps when SKIP_STEPS is provided" do
    bundle_root = Rails.root.join("tmp", "cutover_orchestration_skip_steps")
    FileUtils.mkdir_p(bundle_root)

    step_dirs = {}
    CUTOVER_IMPORT_STEPS.each do |step|
      prefixes = Array(step[:dir_prefixes]).presence || Array(step[:dir_prefix])
      subdir = bundle_root.join("#{prefixes.first}20260605T120000Z")
      FileUtils.mkdir_p(subdir)
      step_dirs[step[:key]] = subdir.to_s
    end

    expected_order = [
      "migration:permissions:import_from_dir",
      "migration:dataset_access_grants:import_from_dir",
      "migration:guides:import_from_dir",
      "migration:spotlights:import_from_dir",
      "migration:medusa_ingests:import_from_dir",
      "migration:download_metrics:import_from_dir",
      "migration:audits:import_from_dir"
    ]

    expected_steps = CUTOVER_IMPORT_STEPS.reject { |step| %w[users datasets].include?(step[:key]) }

    invocations = []
    fake_tasks = {}

    expected_order.each do |task_name|
      task_double = instance_double(Rake::Task)
      allow(task_double).to receive(:reenable)
      allow(task_double).to receive(:invoke) do
        invocations << {
          task: task_name,
          dir: ENV["DIR"],
          bundle_file: ENV["BUNDLE_FILE"],
          dry_run: ENV["DRY_RUN"]
        }
      end
      fake_tasks[task_name] = task_double
    end

    allow(Rake::Task).to receive(:[]).and_wrap_original do |original, task_name|
      fake_tasks.fetch(task_name) { original.call(task_name) }
    end

    ENV["BUNDLE_ROOT"] = bundle_root.to_s
    ENV["DRY_RUN"] = "true"
    ENV["SKIP_STEPS"] = "users,datasets"

    import_all_task.invoke

    expect(invocations.map { |call| call[:task] }).to eq(expected_order)
    expected_steps.each_with_index do |step, index|
      expect(invocations[index][:dir]).to eq(step_dirs[step[:key]])
    end
    expect(invocations).to all(include(dry_run: "true"))
  ensure
    ENV.delete("BUNDLE_ROOT")
    ENV.delete("DRY_RUN")
    ENV.delete("SKIP_STEPS")
    FileUtils.rm_rf(bundle_root)
  end

  it "writes reconciliation report when required runs are present" do
    required_run_types = %w[
      users_bundle_import
      flat_bundle_import
      permissions_bundle_import
      dataset_access_grants_bundle_import
      guides_bundle_import
      featured_researchers_bundle_import
      medusa_ingests_bundle_import
      download_metrics_bundle_import
      audits_bundle_import
    ]

    required_run_types.each_with_index do |run_type, index|
      MigrationRun.create!(
        run_type: run_type,
        status: "completed",
        started_at: Time.current - (index + 1).minutes,
        completed_at: Time.current - index.minutes,
        created_count: 1,
        updated_count: 0,
        skipped_count: 0,
        failed_count: 0,
        processed_count: 1,
        expected_count: 1,
        details: {}
      )
    end

    report_path = Rails.root.join("tmp", "cutover_reconcile_spec.json")
    ENV["REPORT_FILE"] = report_path.to_s

    reconcile_task.invoke

    expect(File.exist?(report_path)).to be(true)
    payload = JSON.parse(File.read(report_path))
    expect(payload["issues"]).to eq([])
    expect(payload["runs"].keys.sort).to eq(required_run_types.sort)
  ensure
    ENV.delete("REPORT_FILE")
    FileUtils.rm_f(report_path)
  end

  it "fails smoke when a required migration run is missing" do
    MigrationRun.delete_all

    run_type = "flat_bundle_import"
    MigrationRun.create!(
      run_type: run_type,
      status: "completed",
      started_at: Time.current - 2.minutes,
      completed_at: Time.current - 1.minute,
      created_count: 1,
      updated_count: 0,
      skipped_count: 0,
      failed_count: 0,
      processed_count: 1,
      expected_count: 1,
      details: {}
    )
    Dataset.create!(
      key: "IDB-9999999",
      title: "Smoke Dataset",
      description: "Smoke",
      owner_uid: "owner-smoke",
      depositor_name: "Owner User",
      depositor_email: "owner-smoke@example.edu"
    )

    report_path = Rails.root.join("tmp", "cutover_smoke_spec.json")
    ENV["REPORT_FILE"] = report_path.to_s

    expect { smoke_task.invoke }.to raise_error(RuntimeError, /cutover smoke failed/)

    payload = JSON.parse(File.read(report_path))
    expect(payload["issues"].any? { |issue| issue.include?("missing migration run") }).to be(true)
  ensure
    ENV.delete("REPORT_FILE")
    FileUtils.rm_f(report_path)
  end
end
