require "rails_helper"

RSpec.describe Metric, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  def metric_config_for(tmpdir)
    {
      datasets_tsv: {
        relative_path: File.join(tmpdir, "datasets.tsv"),
        download_path: "/datasets.tsv",
        content_type: "text/tab-separated-values",
        label: "Datasets TSV",
        summary: "Dataset export"
      },
      datafiles_csv: { relative_path: File.join(tmpdir, "datafiles.csv") },
      container_contents_csv: { relative_path: File.join(tmpdir, "container_contents.csv") },
      funders_csv: { relative_path: File.join(tmpdir, "funders.csv") },
      related_materials_csv: { relative_path: File.join(tmpdir, "related_materials.csv") },
      dataset_report_csv: { relative_path: File.join(tmpdir, "dataset_report.csv") },
      dataset_report_text: { relative_path: File.join(tmpdir, "dataset_report.txt") }
    }
  end

  around do |example|
    Dir.mktmpdir("metric-spec") do |tmpdir|
      @metric_tmpdir = tmpdir
      example.run
    end
  end

  before do
    stub_const("METRICS_CONFIG", metric_config_for(@metric_tmpdir))
    described_class::LOCK_KEYS.each { |key| described_class.clear_in_progress(key) }
  end

  it "dispatches refresh_all to each writer" do
    described_class::LOCK_KEYS.each do |key|
      allow(described_class).to receive("write_#{key}")
    end

    described_class.refresh_all

    described_class::LOCK_KEYS.each do |key|
      expect(described_class).to have_received("write_#{key}")
    end
  end

  it "builds config-backed metric definitions" do
    definition = described_class.definition_for(:datasets_tsv)

    expect(definition.label).to eq("Datasets TSV")
    expect(definition.download_path).to eq("/datasets.tsv")
    expect(definition.content_type).to eq("text/tab-separated-values")
    expect(definition.summary).to include("Dataset export")
  end

  it "tracks lock files and refresh status" do
    expect(described_class.in_progress?(:datasets_tsv)).to be(false)

    described_class.set_in_progress(:datasets_tsv)

    expect(described_class.in_progress?(:datasets_tsv)).to be(true)
    expect(described_class.refresh_status[:datasets_tsv]).to be(true)

    described_class.clear_in_progress(:datasets_tsv)

    expect(described_class.in_progress?(:datasets_tsv)).to be(false)
  end

  it "calculates current fiscal year" do
    travel_to(Time.zone.parse("2026-07-15 12:00:00")) do
      expect(described_class.current_fiscal_year).to eq(27)
    end

    travel_to(Time.zone.parse("2026-06-15 12:00:00")) do
      expect(described_class.current_fiscal_year).to eq(26)
    end
  end

  it "builds year-specific metric filenames" do
    expect(described_class.filename_for_year_metric(:dataset_downloads, 2026, :calendar)).to eq("dataset_downloads_2026.csv")
    expect(described_class.filename_for_year_metric(:datafile_downloads, 26, :fiscal)).to eq("datafile_downloads_FY26.csv")
  end

  it "writes calendar-year dataset downloads CSV filtered to file-public datasets" do
    public_dataset = create(:dataset, :published, key: "IDB-PUB-1", identifier: "10.5555/pub-1", embargo: Dataset::EMBARGO_NONE)
    private_dataset = create(:dataset, :published, key: "IDB-PRIV-1", identifier: "10.5555/priv-1", embargo: Dataset::EMBARGO_METADATA, release_date: Date.current + 90)

    DatasetDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, download_date: Date.new(2025, 1, 15), tally: 3)
    DatasetDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, download_date: Date.new(2026, 1, 15), tally: 2)
    DatasetDownloadTally.create!(dataset_key: private_dataset.key, doi: private_dataset.identifier, download_date: Date.new(2025, 1, 15), tally: 9)

    allow(described_class).to receive(:current_calendar_year).and_return(2025)
    described_class.write_dataset_downloads_csv_by_year(2025, :calendar)

    csv_path = Rails.root.join("public", "dataset_downloads_2025.csv")
    rows = CSV.read(csv_path)

    expect(rows.first).to eq(%w[dataset_key doi download_date tally])
    expect(rows).to include([ public_dataset.key, public_dataset.identifier, "2025-01-15", "3" ])
    expect(rows.flatten).not_to include(private_dataset.key)

    File.delete(csv_path) if File.exist?(csv_path)
  end

  it "writes fiscal-year datafile downloads CSV filtered to fiscal date range" do
    public_dataset = create(:dataset, :published, key: "IDB-PUB-FILE", identifier: "10.5555/pub-file", embargo: Dataset::EMBARGO_NONE)

    FileDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, file_web_id: "f1", filename: "a.csv", download_date: Date.new(2026, 7, 2), tally: 4)
    FileDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, file_web_id: "f2", filename: "b.csv", download_date: Date.new(2027, 6, 15), tally: 5)
    FileDownloadTally.create!(dataset_key: public_dataset.key, doi: public_dataset.identifier, file_web_id: "f3", filename: "c.csv", download_date: Date.new(2026, 6, 15), tally: 8)

    allow(described_class).to receive(:current_fiscal_year).and_return(27)
    described_class.write_datafile_downloads_csv_by_year(27, :fiscal)

    csv_path = Rails.root.join("public", "datafile_downloads_FY27.csv")
    rows = CSV.read(csv_path)

    expect(rows.first).to eq(%w[file_web_id dataset_key doi download_date tally])
    expect(rows).to include([ "f1", public_dataset.key, public_dataset.identifier, "2026-07-02", "4" ])
    expect(rows).to include([ "f2", public_dataset.key, public_dataset.identifier, "2027-06-15", "5" ])
    expect(rows.flatten).not_to include("f3")

    File.delete(csv_path) if File.exist?(csv_path)
  end

  it "retrieves archived metric content from report storage" do
    fake_root = instance_double("ReportRoot")
    fake_io = StringIO.new("dataset_key,doi,download_date,tally\n")

    allow(StorageManager.instance).to receive(:report_root).and_return(fake_root)
    allow(fake_root).to receive(:exist?).with("dataset_downloads_2020.csv").and_return(true)
    allow(fake_root).to receive(:with_input_io).with("dataset_downloads_2020.csv").and_yield(fake_io)

    content = described_class.retrieve_archived_metric_from_storage(:dataset_downloads, 2020, :calendar)

    expect(content).to include("dataset_key,doi")
  end

  it "returns nil when archived metric does not exist" do
    fake_root = instance_double("ReportRoot")
    allow(StorageManager.instance).to receive(:report_root).and_return(fake_root)
    allow(fake_root).to receive(:exist?).and_return(false)

    expect(described_class.retrieve_archived_metric_from_storage(:dataset_downloads, 2020, :calendar)).to be_nil
  end

  it "builds zip for a valid group with current and archived files" do
    require "zip"

    current_filename = "dataset_downloads_2026.csv"
    current_path = Rails.root.join("public", current_filename)
    File.write(current_path, "dataset_key,doi,download_date,tally\nIDB-A,10.1/a,2026-01-01,1\n")

    allow(described_class).to receive(:current_calendar_year).and_return(2026)
    allow(described_class).to receive(:retrieve_archived_metric_from_storage) do |_metric, year, _slice|
      next nil unless year == 2025

      "dataset_key,doi,download_date,tally\nIDB-B,10.1/b,2025-01-01,2\n"
    end

    zip_data = described_class.build_zip_for_group(:dataset_calendar)

    entries = []
    Zip::File.open_buffer(zip_data) do |zip|
      entries = zip.entries.map(&:name)
    end

    expect(entries).to include("dataset_downloads_2026.csv")
    expect(entries).to include("dataset_downloads_2025.csv")
  ensure
    File.delete(current_path) if File.exist?(current_path)
  end
end
