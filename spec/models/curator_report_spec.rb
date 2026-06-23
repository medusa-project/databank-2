require "rails_helper"

RSpec.describe CuratorReport, type: :model do
  let(:storage_root_name) { "reports" }

  it "initiates report generation with normalized notes and enqueues the job" do
    user = create(:user, email: "curator@example.edu", name: "Curator User")

    allow(described_class).to receive(:default_storage_root).and_return(storage_root_name)

    expect do
      @report = described_class.initiate_report_generation(
        report_type: described_class::FILE_AUDIT,
        requesting_user: user,
        notes: "  audit notes  "
      )
    end.to have_enqueued_job(CuratorReportJob)

    expect(@report.requestor_name).to eq("Curator User")
    expect(@report.requestor_email).to eq("curator@example.edu")
    expect(@report.report_type).to eq(described_class::FILE_AUDIT)
    expect(@report.storage_root).to eq(storage_root_name)
    expect(@report.notes).to eq("  audit notes  ")
    expect(@report.storage_key).to start_with("file_audit_report-#{@report.id}_")
    expect(@report.storage_key).to end_with(".csv")
  end

  it "uses the storage manager report root name as the default storage root" do
    report_root = instance_double("ReportRoot", name: storage_root_name)
    storage_manager = instance_double(StorageManager, report_root: report_root)

    allow(StorageManager).to receive(:instance).and_return(storage_manager)

    expect(described_class.default_storage_root).to eq(storage_root_name)
  end

  it "dispatches known report types and rejects unknown ones" do
    report = described_class.new(report_type: described_class::FILE_AUDIT)

    allow(described_class).to receive(:generate_file_audit_report)

    described_class.generate_report(report)
    expect(described_class).to have_received(:generate_file_audit_report).with(report)

    expect do
      described_class.generate_report(described_class.new(report_type: "unknown"))
    end.to raise_error(RuntimeError, "Unknown report type: unknown")
  end

  it "writes the file audit CSV to the report storage root" do
    dataset = create(
      :dataset,
      title: "Dataset for Audit",
      publication_state: :published,
      identifier: "10.5555/dataset-for-audit",
      release_date: Date.current,
      embargo: Dataset::EMBARGO_NONE
    )
    datafile = create(:datafile, dataset: dataset)
    datafile.update!(storage_root: "draft", binary_size: 123)
    report = described_class.create!(
      requestor_name: "Curator",
      requestor_email: "curator@example.edu",
      report_type: described_class::FILE_AUDIT,
      storage_root: storage_root_name,
      storage_key: "file-audit.csv"
    )

    root = instance_double("ReportRoot")
    captured_csv = nil

    allow(report).to receive(:current_root).and_return(root)
    allow_any_instance_of(Datafile).to receive(:exists_on_storage?).and_return(true)
    allow(IdbConfig).to receive(:fetch).and_call_original
    allow(IdbConfig).to receive(:fetch).with(:app, :root_url_text, default: "http://localhost:3000").and_return("https://databank.test")
    allow(root).to receive(:copy_io_to) do |_key, io, _content_type, _size|
      captured_csv = io.read
    end

    described_class.generate_file_audit_report(report)

    expect(root).to have_received(:copy_io_to).with("file-audit.csv", instance_of(StringIO), nil, kind_of(Integer))
    expect(captured_csv).to include("File Name,Storage Root,File Size (bytes),File Status,File URL,Dataset Title,Dataset URL,Publication State")
    expect(captured_csv).to include(datafile.binary_name)
    expect(captured_csv).to include("draft")
    expect(captured_csv).to include("analysis.csv,draft,123,exists,")
    expect(captured_csv).to include("Dataset for Audit")
    expect(captured_csv).to include("https://databank.test/datasets/#{dataset.key}")
    expect(captured_csv).to include("https://databank.test/datasets/#{dataset.key}/datafiles/#{datafile.web_id}/download")
  end

  it "builds download links and current root from storage manager" do
    report = described_class.create!(
      requestor_name: "Curator",
      requestor_email: "curator@example.edu",
      report_type: described_class::FILE_AUDIT,
      storage_root: storage_root_name,
      storage_key: "file-audit.csv"
    )
    root = instance_double("ReportRoot")
    root_set = instance_double("RootSet", at: root)
    storage_manager = instance_double(StorageManager, root_set: root_set)

    allow(StorageManager).to receive(:instance).and_return(storage_manager)

    expect(report.download_link).to eq("/curator_reports/#{report.id}/download")
    expect(report.current_root).to eq(root)
  end

  it "reports pending, generating, and available statuses with matching label classes" do
    report = described_class.create!(
      requestor_name: "Curator",
      requestor_email: "curator@example.edu",
      report_type: described_class::FILE_AUDIT,
      storage_root: storage_root_name,
      storage_key: "file-audit.csv",
      created_at: 30.minutes.ago
    )
    root = instance_double("ReportRoot")

    allow(report).to receive(:current_root).and_return(root)
    allow(root).to receive(:exist?).with("file-audit.csv").and_return(false)

    expect(report.status).to eq("pending")
    expect(report.status_label_class).to eq("label-default")

    report.update_column(:created_at, 2.hours.ago)
    expect(report.status).to eq("generating")
    expect(report.status_label_class).to eq("label-warning")

    allow(root).to receive(:exist?).with("file-audit.csv").and_return(true)
    expect(report.status).to eq("available")
    expect(report.status_label_class).to eq("label-success")
  end

  it "treats missing storage information as pending" do
    report = described_class.create!(
      requestor_name: "Curator",
      requestor_email: "curator@example.edu",
      report_type: described_class::FILE_AUDIT,
      storage_root: nil,
      storage_key: nil
    )

    expect(report.status).to eq("pending")
    expect(report.status_label_class).to eq("label-default")
  end

  it "removes the report file and metadata file when destroyed" do
    report = described_class.create!(
      requestor_name: "Curator",
      requestor_email: "curator@example.edu",
      report_type: described_class::FILE_AUDIT,
      storage_root: storage_root_name,
      storage_key: "file-audit.csv"
    )
    root = instance_double("ReportRoot")

    allow(report).to receive(:current_root).and_return(root)
    allow(root).to receive(:exist?).with("file-audit.csv").and_return(true)
    allow(root).to receive(:exist?).with("file-audit.csv.info").and_return(true)
    allow(root).to receive(:delete_content)

    report.destroy

    expect(root).to have_received(:delete_content).with("file-audit.csv")
    expect(root).to have_received(:delete_content).with("file-audit.csv.info")
  end
end
