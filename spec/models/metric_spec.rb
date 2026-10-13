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
    FileUtils.mkdir_p(File.join(@metric_tmpdir, "public"))
    allow(Rails.root).to receive(:join).and_wrap_original do |original, *parts|
      parts.first == "public" ? Pathname(@metric_tmpdir).join(*parts) : original.call(*parts)
    end
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

    entries = {}
    Zip::File.open_buffer(zip_data) do |zip|
      zip.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end

    expect(entries).to eq(
      "dataset_downloads_2026.csv" => "dataset_key,doi,download_date,tally\nIDB-A,10.1/a,2026-01-01,1\n",
      "dataset_downloads_2025.csv" => "dataset_key,doi,download_date,tally\nIDB-B,10.1/b,2025-01-01,2\n"
    )
  ensure
    File.delete(current_path) if File.exist?(current_path)
  end

  describe "metadata exports" do
    let(:published_dataset) do
      create(:dataset, publication_state: :published, identifier: "10.5555/export",
        title: 'Measurements, "quoted"', description: "Export description",
        keywords: "water,soil", subject: "Environmental Science",
        published_at: Time.zone.parse("2024-02-03 12:00:00"), release_date: Date.new(2024, 2, 3))
    end
    let(:attachment) { create(:datafile, dataset: published_dataset) }
    let(:archive) do
      create(:datafile, dataset: published_dataset, attach_binary: false,
        binary_name: "bundle.zip", binary_size: 123, peek_type: Datafile::PeekType::LISTING)
    end

    before do
      attachment
      archive.nested_items.create!(
        item_name: "table.csv", item_path: "folder/table.csv", media_type: "text/csv", size: 42
      )
      create(:creator, dataset: published_dataset, given_name: "Alice", family_name: "Example",
        email: "alice@example.edu", contact: true)
      published_dataset.reload.save!
      published_dataset.funders.create!(name: 'Foundation, "A"', grant: "GRANT-1")
      legacy_funder = published_dataset.funders.create!(name: "Legacy Foundation", award_number: "AWARD-2")
      legacy_funder.update_columns(grant: nil)
      published_dataset.related_materials.create!(
        title: "Related article", uri: "https://example.test/article", uri_type: "URL",
        datacite_list: "IsSupplementTo,IsCitedBy", selected_type: "Article", material_type: "Legacy article"
      )
      published_dataset.related_materials.create!(
        title: "Earlier version", uri: "https://example.test/previous", uri_type: "URL",
        relation_type: RelatedMaterial::VERSION_PREVIOUS_RELATION
      )
      DatasetDownloadTally.create!(
        dataset_key: published_dataset.key, download_date: Date.new(2024, 3, 1), tally: 7
      )
      FileDownloadTally.create!(
        file_web_id: attachment.web_id, download_date: Date.new(2024, 3, 1), tally: 3
      )
    end

    it "writes the dataset TSV with exact columns, aggregates, and non-version relationship count" do
      described_class.write_datasets_tsv

      rows = CSV.read(METRICS_CONFIG[:datasets_tsv][:relative_path], col_sep: "\t", quote_char: nil)
      expect(rows).to eq([
        %w[doi ingest_date release_date num_files num_bytes total_downloads num_relationships num_creators subject citation_text],
        [
          published_dataset.identifier, published_dataset.created_at.to_date.iso8601, "2024-02-03",
          "2", (attachment.binary_size + 123).to_s, "7", "1", "1",
          "Environmental Science", published_dataset.plain_text_citation
        ]
      ])
      expect(described_class.in_progress?(:datasets_tsv)).to be(false)
    end

    it "writes file CSV rows with attachment and filename-derived MIME types" do
      described_class.write_datafiles_csv

      rows = CSV.read(METRICS_CONFIG[:datafiles_csv][:relative_path])
      expect(rows.shift).to eq(%w[doi pub_date filename file_format num_bytes total_downloads])
      expect(rows).to contain_exactly(
        [ published_dataset.identifier, "2024-02-03", attachment.binary_name, "text/csv", attachment.binary_size.to_s, "3" ],
        [ published_dataset.identifier, "2024-02-03", "bundle.zip", "application/zip", "123", "0" ]
      )
    end

    it "exports nested items only from archive files" do
      attachment.nested_items.create!(item_name: "not-an-archive.txt", item_path: "ignored.txt", media_type: "text/plain")
      described_class.write_container_contents_csv

      expect(CSV.read(METRICS_CONFIG[:container_contents_csv][:relative_path])).to eq([
        %w[doi container_filename content_filepath content_filename file_format],
        [ published_dataset.identifier, "bundle.zip", "folder/table.csv", "table.csv", "text/csv" ]
      ])
    end

    it "round-trips quoted funder names and falls back to legacy award numbers" do
      described_class.write_funders_csv

      rows = CSV.read(METRICS_CONFIG[:funders_csv][:relative_path])
      expect(rows.shift).to eq(%w[doi funder grant])
      expect(rows).to contain_exactly(
        [ published_dataset.identifier, 'Foundation, "A"', "GRANT-1" ],
        [ published_dataset.identifier, "Legacy Foundation", "AWARD-2" ]
      )
    end

    it "expands related-material relationships and omits both version relations" do
      legacy = published_dataset.related_materials.create!(
        title: "Legacy material", uri: "https://example.test/legacy", uri_type: "URL",
        relation_type: "IsSupplementedBy", material_type: "Report"
      )
      legacy.update_columns(datacite_list: nil)
      published_dataset.related_materials.create!(
        title: "Newer version", uri: "https://example.test/next", uri_type: "URL",
        relation_type: RelatedMaterial::VERSION_NEW_RELATION
      )
      described_class.write_related_materials_csv

      rows = CSV.read(METRICS_CONFIG[:related_materials_csv][:relative_path])
      expect(rows.shift).to eq(%w[doi datacite_relationship material_id_type material_id material_type])
      expect(rows).to contain_exactly(
        [ published_dataset.identifier, "IsSupplementTo", "URL", "https://example.test/article", "Article" ],
        [ published_dataset.identifier, "IsCitedBy", "URL", "https://example.test/article", "Article" ],
        [ published_dataset.identifier, "IsSupplementedBy", "URL", "https://example.test/legacy", "Report" ]
      )
    end

    it "writes CSV and text dataset reports with funders, contact, and citation" do
      described_class.generate_datasets_reports

      expect(CSV.read(METRICS_CONFIG[:dataset_report_csv][:relative_path])).to eq([
        %w[key doi release_date funders title keywords corresponding_creator subject],
        [
          published_dataset.key, published_dataset.identifier, "2024-02-03",
          'Foundation, "A" (GRANT-1); Legacy Foundation (AWARD-2)',
          'Measurements, "quoted"', "water,soil",
          "Alice Example | alice@example.edu", "Environmental Science"
        ]
      ])
      text = File.read(METRICS_CONFIG[:dataset_report_text][:relative_path])
      expect(text).to eq(
        "Key: #{published_dataset.key}\nCitation: #{published_dataset.plain_text_citation}\n" \
        "Description: Export description\n----------------------------------------\n\n"
      )
    end

    {
      draft: { publication_state: :draft },
      test_dataset: { is_test: true },
      metadata_embargo: { embargo: Dataset::EMBARGO_METADATA, release_date: Date.current + 30 },
      temporary_suppression: { hold_state: Dataset::HOLD_TEMP_METADATA },
      permanent_suppression: { hold_state: Dataset::HOLD_PERM_METADATA },
      version_candidate: { hold_state: Dataset::HOLD_TEMP_VERSION }
    }.each do |state, attributes|
      it "excludes #{state} datasets from every metadata export and dataset report" do
        hidden = create(:dataset, **attributes.merge(identifier: "10.5555/hidden", publication_state: attributes.fetch(:publication_state, :published)))
        hidden_file = create(:datafile, dataset: hidden, attach_binary: false,
          binary_name: "hidden.zip", peek_type: Datafile::PeekType::LISTING)
        hidden_file.nested_items.create!(item_name: "hidden.txt", item_path: "hidden.txt")
        hidden.funders.create!(name: "Hidden Funder", grant: "HIDDEN")
        hidden.related_materials.create!(title: "Hidden article", uri: "https://example.test/hidden", relation_type: "IsCitedBy")

        described_class.refresh_all
        described_class.generate_datasets_reports

        METRICS_CONFIG.each_value do |config|
          content = File.read(config[:relative_path])
          expect(content).to include(published_dataset.identifier)
          expect(content).not_to include(hidden.identifier, hidden.key, "Hidden Funder", "hidden.txt")
        end
      end
    end
  end

  {
    datasets_tsv: %w[doi ingest_date release_date num_files num_bytes total_downloads num_relationships num_creators subject citation_text],
    datafiles_csv: %w[doi pub_date filename file_format num_bytes total_downloads],
    container_contents_csv: %w[doi container_filename content_filepath content_filename file_format],
    funders_csv: %w[doi funder grant],
    related_materials_csv: %w[doi datacite_relationship material_id_type material_id material_type]
  }.each do |key, headings|
    describe "write_#{key}" do
      it "writes only the header when there are no public datasets" do
        described_class.public_send("write_#{key}")

        separator = key == :datasets_tsv ? "\t" : ","
        expect(CSV.read(METRICS_CONFIG[key][:relative_path], col_sep: separator)).to eq([ headings ])
        expect(described_class.in_progress?(key)).to be(false)
      end

      it "propagates write failures and always removes its lock" do
        path = METRICS_CONFIG[key][:relative_path]
        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:open).with(path, "w") do
          expect(described_class.in_progress?(key)).to be(true)
          raise IOError, "disk full"
        end

        expect { described_class.public_send("write_#{key}") }.to raise_error(IOError, "disk full")
        expect(described_class.in_progress?(key)).to be(false)
      end
    end
  end

  describe "download export archival" do
    let(:report_root) { instance_double(StorageManager.instance.report_root.class) }

    before do
      allow(StorageManager.instance).to receive(:report_root).and_return(report_root)
      allow(described_class).to receive(:current_calendar_year).and_return(2026)
      allow(described_class).to receive(:current_fiscal_year).and_return(27)
    end

    %i[dataset_downloads datafile_downloads].each do |type|
      describe type.to_s do
        let(:filename) { "#{type}_2025.csv" }
        let(:path) { Rails.root.join("public", filename) }
        let(:headings) do
          type == :dataset_downloads ? Metric::DATASET_DOWNLOADS_CSV_HEADINGS : Metric::DATAFILE_DOWNLOADS_CSV_HEADINGS
        end

        it "archives generated historical content before removing the local file" do
          dataset = create(:dataset, publication_state: :published, identifier: "10.5555/archived")
          if type == :dataset_downloads
            DatasetDownloadTally.create!(dataset_key: dataset.key, doi: dataset.identifier,
              download_date: Date.new(2025, 1, 2), tally: 4)
            expected_row = [ dataset.key, dataset.identifier, "2025-01-02", "4" ]
          else
            FileDownloadTally.create!(file_web_id: "abc12", dataset_key: dataset.key, doi: dataset.identifier,
              download_date: Date.new(2025, 1, 2), tally: 4)
            expected_row = [ "abc12", dataset.key, dataset.identifier, "2025-01-02", "4" ]
          end
          expect(report_root).to receive(:copy_io_to).with(filename, anything, nil, anything) do |_key, io, _checksum, size|
            expect(path).to exist
            expect(File).to exist("#{path}.lock")
            content = io.read
            expect(size).to eq(content.bytesize)
            expect(CSV.parse(content)).to eq([ headings, expected_row ])
          end

          described_class.public_send("write_#{type}_csv_by_year", 2025, :calendar)

          expect(path).not_to exist
          expect(File).not_to exist("#{path}.lock")
        end

        it "preserves the local file and clears the lock if the storage copy fails" do
          allow(report_root).to receive(:copy_io_to).and_raise(IOError, "storage unavailable")

          expect do
            described_class.public_send("write_#{type}_csv_by_year", 2025, :calendar)
          end.to raise_error(IOError, "storage unavailable")
          expect(CSV.read(path)).to eq([ headings ])
          expect(File).not_to exist("#{path}.lock")
        end

        it "keeps the current year's export local without accessing archive storage" do
          expect(report_root).not_to receive(:copy_io_to)

          described_class.public_send("write_#{type}_csv_by_year", 2026, :calendar)

          expect(CSV.read(Rails.root.join("public", "#{type}_2026.csv"))).to eq([ headings ])
        end

        it "clears the year-specific lock when CSV generation fails" do
          allow(CSV).to receive(:open).with(path, "w") do
            expect(File).to exist("#{path}.lock")
            raise IOError, "disk full"
          end

          expect do
            described_class.public_send("write_#{type}_csv_by_year", 2025, :calendar)
          end.to raise_error(IOError, "disk full")
          expect(File).not_to exist("#{path}.lock")
        end
      end

      describe "download export visibility and date boundaries" do
        {
          calendar: [ 2026, Date.new(2026, 1, 1), Date.new(2026, 12, 31) ],
          fiscal: [ 27, Date.new(2026, 7, 1), Date.new(2027, 6, 30) ]
        }.each do |slice, (year, first_day, last_day)|
          it "includes both #{slice} boundaries and excludes non-public files in #{type}" do
            public_dataset = create(:dataset, publication_state: :published, identifier: "10.5555/boundaries")
            dates = [ first_day - 1, first_day, last_day, last_day + 1 ]
            tally_class = type == :dataset_downloads ? DatasetDownloadTally : FileDownloadTally
            dates.each do |date|
              attributes = {
                dataset_key: public_dataset.key, doi: public_dataset.identifier,
                download_date: date, tally: 2
              }
              attributes[:file_web_id] = "abc12" if type == :datafile_downloads
              tally_class.create!(**attributes)
            end
            [
              { publication_state: :draft },
              { is_test: true },
              { embargo: Dataset::EMBARGO_FILE, release_date: Date.current + 30 },
              { embargo: Dataset::EMBARGO_METADATA, release_date: Date.current + 30 },
              { hold_state: Dataset::HOLD_TEMP_FILE },
              { hold_state: Dataset::HOLD_PERM_FILE },
              { hold_state: Dataset::HOLD_TEMP_METADATA }
            ].each do |visibility|
              hidden = create(:dataset, publication_state: :published, **visibility)
              attributes = { dataset_key: hidden.key, download_date: first_day, tally: 99 }
              attributes[:file_web_id] = "hidden-#{hidden.id}" if type == :datafile_downloads
              tally_class.create!(**attributes)
            end
            allow(described_class).to receive(:current_calendar_year).and_return(2026)
            allow(described_class).to receive(:current_fiscal_year).and_return(27)

            described_class.public_send("write_#{type}_csv_by_year", year, slice)

            filename = described_class.filename_for_year_metric(type, year, slice)
            rows = CSV.read(Rails.root.join("public", filename))
            headings = type == :dataset_downloads ? Metric::DATASET_DOWNLOADS_CSV_HEADINGS : Metric::DATAFILE_DOWNLOADS_CSV_HEADINGS
            expect(rows.shift).to eq(headings)
            expected = [ first_day, last_day ].map do |date|
              row = [ public_dataset.key, public_dataset.identifier, date.iso8601, "2" ]
              type == :datafile_downloads ? [ "abc12", *row ] : row
            end
            expect(rows).to contain_exactly(*expected)
          end
        end
      end
    end

    it "logs archive read failures and returns nil" do
      allow(report_root).to receive(:exist?).with("dataset_downloads_2025.csv").and_return(true)
      allow(report_root).to receive(:with_input_io).and_raise(IOError, "storage unavailable")
      allow(Rails.logger).to receive(:error)

      expect(described_class.retrieve_archived_metric_from_storage(:dataset_downloads, 2025, :calendar)).to be_nil
      expect(Rails.logger).to have_received(:error).with(
        "Error retrieving archived metric dataset_downloads_2025.csv: storage unavailable"
      )
    end

    it "archives existing prior-year files without removing current-year files" do
      prior_path = Rails.root.join("public", "dataset_downloads_2025.csv")
      current_path = Rails.root.join("public", "dataset_downloads_2026.csv")
      File.write(prior_path, "prior year\n")
      File.write(current_path, "current year\n")
      expect(report_root).to receive(:copy_io_to).with("dataset_downloads_2025.csv", anything, nil, 11).once do |_key, io|
        expect(io.read).to eq("prior year\n")
      end

      described_class.archive_prior_year_downloads_to_storage

      expect(prior_path).not_to exist
      expect(File.read(current_path)).to eq("current year\n")
    end
  end
end
