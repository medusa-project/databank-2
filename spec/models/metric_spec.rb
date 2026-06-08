require "rails_helper"

RSpec.describe Metric, type: :model do
  def metric_config_for(tmpdir)
    {
      dataset_downloads_json: { relative_path: File.join(tmpdir, "dataset_downloads.json") },
      datafile_downloads_json: { relative_path: File.join(tmpdir, "datafile_downloads.json") },
      datasets_tsv: { relative_path: File.join(tmpdir, "datasets.tsv") },
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

  it "tracks lock files and refresh status" do
    expect(described_class.in_progress?(:datasets_tsv)).to be(false)

    described_class.set_in_progress(:datasets_tsv)

    expect(described_class.in_progress?(:datasets_tsv)).to be(true)
    expect(described_class.refresh_status[:datasets_tsv]).to be(true)

    described_class.clear_in_progress(:datasets_tsv)

    expect(described_class.in_progress?(:datasets_tsv)).to be(false)
  end

  it "ensures missing metric files exist when reading modified times" do
    allow(described_class).to receive(:write_dataset_downloads_json) do
      File.write(METRICS_CONFIG[:dataset_downloads_json][:relative_path], "{}")
    end
    allow(described_class).to receive(:write_datafile_downloads_json) do
      File.write(METRICS_CONFIG[:datafile_downloads_json][:relative_path], "{}")
    end
    allow(described_class).to receive(:write_datasets_tsv) do
      File.write(METRICS_CONFIG[:datasets_tsv][:relative_path], "header\n")
    end
    allow(described_class).to receive(:write_datafiles_csv) do
      File.write(METRICS_CONFIG[:datafiles_csv][:relative_path], "header\n")
    end
    allow(described_class).to receive(:write_container_contents_csv) do
      File.write(METRICS_CONFIG[:container_contents_csv][:relative_path], "header\n")
    end
    allow(described_class).to receive(:write_funders_csv) do
      File.write(METRICS_CONFIG[:funders_csv][:relative_path], "header\n")
    end
    allow(described_class).to receive(:write_related_materials_csv) do
      File.write(METRICS_CONFIG[:related_materials_csv][:relative_path], "header\n")
    end

    modified_times = described_class.modified_times

    expect(modified_times.keys).to match_array(described_class::LOCK_KEYS)
    described_class::LOCK_KEYS.each do |key|
      expect(File.exist?(METRICS_CONFIG[key][:relative_path])).to be(true)
      expect(modified_times[key]).to eq(File.mtime(METRICS_CONFIG[key][:relative_path]).to_fs(:long))
    end
  end

  it "writes dataset downloads json and aggregate totals" do
    DatasetDownloadTally.create!(dataset_key: "IDB-1", doi: "10.5555/one", download_date: Date.new(2026, 6, 1), tally: 2)
    DatasetDownloadTally.create!(dataset_key: "IDB-1", doi: "10.5555/one", download_date: Date.new(2026, 6, 2), tally: 3)
    DatasetDownloadTally.create!(dataset_key: "IDB-2", doi: nil, download_date: Date.new(2026, 6, 3), tally: 7)

    described_class.write_dataset_downloads_json

    json_path = METRICS_CONFIG[:dataset_downloads_json][:relative_path]
    totals_path = json_path.sub(/\.json\z/, "_totals.csv")
    parsed = JSON.parse(File.read(json_path))

    expect(parsed.fetch("dataset_downloads")).to eq([
      { "doi" => "10.5555/one", "date" => "2026-06-01", "tally" => 2 },
      { "doi" => "10.5555/one", "date" => "2026-06-02", "tally" => 3 },
      { "doi" => nil, "date" => "2026-06-03", "tally" => 7 }
    ])
    expect(File.read(totals_path)).to include("doi,tally")
    expect(File.read(totals_path)).to include("10.5555/one,5")
  end

  it "writes datafiles csv using attachment and filename mime types" do
    dataset = create(:dataset, :published, identifier: "10.5555/metrics-files", release_date: Date.new(2026, 6, 8))
    attached = create(:datafile, dataset: dataset)
    detached = create(:datafile, dataset: dataset, attach_binary: false, binary_name: "archive.zip", binary_size: 99)

    described_class.write_datafiles_csv

    csv_rows = CSV.read(METRICS_CONFIG[:datafiles_csv][:relative_path])

    expect(csv_rows.first).to eq(%w[doi pub_date filename file_format num_bytes total_downloads])
    expect(csv_rows).to include([
      "10.5555/metrics-files",
      "2026-06-08",
      attached.binary_name,
      "text/csv",
      attached.binary_size.to_i.to_s,
      "0"
    ])
    expect(csv_rows).to include([
      "10.5555/metrics-files",
      "2026-06-08",
      "archive.zip",
      "application/zip",
      "99",
      "0"
    ])
  end

  it "writes related materials csv while skipping version relations" do
    dataset = create(:dataset, :published, identifier: "10.5555/related-materials")
    dataset.related_materials.create!(
      title: "Supplementary spreadsheet",
      relation_type: "IsSupplementTo",
      datacite_list: "IsSupplementTo, IsCitedBy",
      uri_type: "DOI",
      uri: "https://doi.org/10.1234/example",
      selected_type: "Dataset"
    )
    dataset.related_materials.create!(
      title: "Previous version",
      relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION,
      uri_type: "DOI",
      uri: "https://doi.org/10.1234/previous",
      material_type: "Dataset"
    )

    described_class.write_related_materials_csv

    csv_rows = CSV.read(METRICS_CONFIG[:related_materials_csv][:relative_path])

    expect(csv_rows.first).to eq(%w[doi datacite_relationship material_id_type material_id material_type])
    expect(csv_rows).to include([
      "10.5555/related-materials",
      "IsSupplementTo",
      "DOI",
      "https://doi.org/10.1234/example",
      "Dataset"
    ])
    expect(csv_rows).to include([
      "10.5555/related-materials",
      "IsCitedBy",
      "DOI",
      "https://doi.org/10.1234/example",
      "Dataset"
    ])
    expect(csv_rows.flatten).not_to include(RelatedMaterial::VERSION_PREVIOUS_RELATION)
  end

  it "generates dataset report csv and text exports" do
    dataset = create(
      :dataset,
      :published,
      title: "Metrics Report Dataset",
      key: "IDB-7777777",
      identifier: "10.5555/report-dataset",
      release_date: Date.new(2026, 6, 8),
      keywords: "metrics,reporting",
      corresponding_creator_name: "Contact Creator",
      corresponding_creator_email: "contact@example.edu",
      description: "Dataset report body",
      subject: "Physics",
      published_at: Time.zone.parse("2026-06-08 10:00:00")
    )
    dataset.creators.destroy_all
    dataset.creators.create!(name: "Jane Creator", email: "jane@example.edu", contact: true, row_position: 1)
    dataset.funders.create!(name: "NSF", grant: "PHY-123")

    described_class.generate_datasets_reports

    csv_rows = CSV.read(METRICS_CONFIG[:dataset_report_csv][:relative_path])
    text_report = File.read(METRICS_CONFIG[:dataset_report_text][:relative_path])

    expect(csv_rows.first).to eq(%w[key doi release_date funders title keywords corresponding_creator subject])
    expect(csv_rows).to include([
      "IDB-7777777",
      "10.5555/report-dataset",
      "2026-06-08",
      "NSF (PHY-123)",
      "Metrics Report Dataset",
      "metrics,reporting",
      "Jane Creator | jane@example.edu",
      "Physics"
    ])
    expect(text_report).to include("Key: IDB-7777777")
    expect(text_report).to include("Citation: Jane Creator (2026) Metrics Report Dataset. Illinois Data Bank https://doi.org/10.5555/report-dataset")
    expect(text_report).to include("Description: Dataset report body")
  end
end
