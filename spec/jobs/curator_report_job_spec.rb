require "rails_helper"

RSpec.describe CuratorReportJob, type: :job do
  it "loads the report and generates it" do
    report = CuratorReport.create!(
      requestor_name: "Curator",
      requestor_email: "curator@example.edu",
      report_type: CuratorReport::FILE_AUDIT,
      storage_root: "reports",
      storage_key: "reports/file.csv"
    )
    allow(CuratorReport).to receive(:generate_report)

    described_class.perform_now(report.id)

    expect(CuratorReport).to have_received(:generate_report).with(report)
  end
end
