require "rails_helper"

RSpec.describe ArchiveExtractor::MockInvoker, type: :service do
  let(:datafile) { create(:datafile) }

  it "creates and persists a sent archive extract request with mock metadata" do
    fixed_time = Time.zone.parse("2026-06-08 12:00:00")
    allow(Time).to receive(:current).and_return(fixed_time)

    begin
      request = described_class.new.invoke_extraction(datafile)

      expect(request).to be_persisted
      expect(request.status).to eq("sent")
      expect(request.sent_at).to eq(fixed_time)
      expect(JSON.parse(request.raw_response)).to include("mock" => true, "invoked_at" => fixed_time.iso8601)
      expect(datafile.reload.archive_extract_request).to eq(request)
    ensure
      allow(Time).to receive(:current).and_call_original
    end
  end

  it "reuses an existing request for the datafile" do
    existing = ArchiveExtractRequest.create!(datafile: datafile, status: :pending)

    request = described_class.new.invoke_extraction(datafile)

    expect(request.id).to eq(existing.id)
    expect(request.status).to eq("sent")
  end

  it "requires a datafile" do
    expect do
      described_class.new.invoke_extraction(nil)
    end.to raise_error(ArgumentError, "datafile is required")
  end

  it "reports zero running tasks" do
    expect(described_class.new.current_task_count).to eq(0)
  end
end
