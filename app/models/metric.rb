# frozen_string_literal: true

require "csv"
require "fileutils"
require "stringio"

class Metric
  LOCK_KEYS = %i[
    datasets_tsv
    datafiles_csv
    container_contents_csv
    funders_csv
    related_materials_csv
  ].freeze
  MIMETYPE_DEFAULT = "application/octet-stream"
  FIRST_DOWNLOAD_CALENDAR_YEAR = 2016
  FIRST_DOWNLOAD_FISCAL_YEAR = 16
  FISCAL_YEAR_START_MONTH = 7
  DATASET_DOWNLOADS_CSV_HEADINGS = %w[dataset_key doi download_date tally].freeze
  DATAFILE_DOWNLOADS_CSV_HEADINGS = %w[file_web_id dataset_key doi download_date tally].freeze
  DOWNLOAD_ZIP_GROUPS = %i[dataset_calendar dataset_fiscal datafile_calendar datafile_fiscal].freeze

  Definition = Struct.new(:key, :config, keyword_init: true) do
    def label
      config_value(:label) || key.to_s.tr("_", " ")
    end

    def relative_path
      config_value(:relative_path).to_s
    end

    def download_path
      path = config_value(:download_path)
      return path if path.present?

      absolute_path = relative_path
      root_prefix = Rails.root.to_s
      return absolute_path.delete_prefix(root_prefix) if absolute_path.start_with?(root_prefix)

      "/#{File.basename(absolute_path)}"
    end

    def content_type
      config_value(:content_type) || begin
        case File.extname(relative_path)
        when ".json"
          "application/json"
        when ".csv"
          "text/csv"
        when ".tsv"
          "text/tab-separated-values"
        when ".txt"
          "text/plain"
        else
          MIMETYPE_DEFAULT
        end
      end
    end

    def summary
      config_value(:summary)
    end

    def description_blocks
      config_value(:description_blocks) || []
    end

    def columns
      config_value(:columns) || []
    end

    def show_in_admin?
      explicit_value = config_value(:show_in_admin)
      return explicit_value unless explicit_value.nil?

      refreshable?
    end

    def refreshable?
      explicit_value = config_value(:refreshable)
      return explicit_value unless explicit_value.nil?

      Metric::LOCK_KEYS.include?(key)
    end

    def writer_method
      configured_method = config_value(:write_method)
      return configured_method.to_sym if configured_method.present?

      "write_#{key}".to_sym
    end

    def lock_path
      "#{relative_path}.lock"
    end

    def in_progress?
      File.exist?(lock_path)
    end

    private

    def config_value(name)
      config.key?(name) ? config[name] : config[name.to_s]
    end
  end

  class << self
    def refresh_all
      refreshable_definitions.each do |definition|
        public_send(writer_method_for(definition.key))
      end
    end

    def lock_path(metric_key)
      definition_for(metric_key).lock_path
    end

    def in_progress?(metric_key)
      definition_for(metric_key).in_progress?
    end

    def refresh_status
      refreshable_definitions.each_with_object({}) do |definition, statuses|
        statuses[definition.key] = definition.in_progress?
      end
    end

    def set_in_progress(metric_key)
      FileUtils.touch(lock_path(metric_key))
    end

    def clear_in_progress(metric_key)
      path = lock_path(metric_key)
      File.delete(path) if File.exist?(path)
    end

    def modified_times
      ensure_metrics_exist!

      refreshable_definitions.each_with_object({}) do |definition, modified|
        modified[definition.key] = format_mtime(definition.key)
      end
    end

    def ensure_fresh_metrics
      refreshable_definitions.each do |definition|
        path = definition.relative_path

        if !File.exist?(path) || File.mtime(path) < 1.day.ago
          public_send(writer_method_for(definition.key))
        end
      end
    end

    def ensure_download_metrics
      current_cal_year = current_calendar_year
      current_fis_year = current_fiscal_year

      %i[dataset_downloads datafile_downloads].each do |metric_type|
        [ [ current_cal_year, :calendar ], [ current_fis_year, :fiscal ] ].each do |year, slice_type|
          filename = filename_for_year_metric(metric_type, year, slice_type)
          path = Rails.root.join("public", filename)
          if !File.exist?(path) || File.mtime(path) < 1.day.ago
            public_send("write_#{metric_type}_csv_by_year", year, slice_type)
          end
        end
      end
    end

    def current_calendar_year
      Time.zone.now.year
    end

    def current_fiscal_year
      now = Time.zone.now
      return (now.year + 1) % 100 if now.month >= FISCAL_YEAR_START_MONTH

      now.year % 100
    end

    def date_range_for_fiscal_year(fiscal_year)
      start_year = 2000 + fiscal_year - 1
      start_date = Date.new(start_year, FISCAL_YEAR_START_MONTH, 1)
      end_date = Date.new(start_year + 1, FISCAL_YEAR_START_MONTH, 1) - 1.day
      [ start_date, end_date ]
    end

    def year_is_current?(year, slice_type)
      case slice_type
      when :calendar
        year == current_calendar_year
      when :fiscal
        year == current_fiscal_year
      else
        raise ArgumentError, "Invalid slice_type: #{slice_type}"
      end
    end

    def filename_for_year_metric(metric_type, year, slice_type)
      base = metric_type.to_s
      suffix = slice_type == :fiscal ? "FY#{year.to_s.rjust(2, '0')}" : year.to_s
      "#{base}_#{suffix}.csv"
    end

    def storage_key_for_archived_metric(metric_type, year, slice_type)
      filename_for_year_metric(metric_type, year, slice_type)
    end

    def year_metric_available?(metric_type:, year:, slice_type:)
      if year_is_current?(year, slice_type)
        filename = filename_for_year_metric(metric_type, year, slice_type)
        return File.exist?(Rails.root.join("public", filename))
      end

      archived_metric_exists?(metric_type, year, slice_type)
    rescue StandardError
      false
    end

    def archived_metric_exists?(metric_type, year, slice_type)
      storage_key = storage_key_for_archived_metric(metric_type, year, slice_type)
      StorageManager.instance.report_root.exist?(storage_key)
    rescue StandardError => error
      Rails.logger.error("Error checking archived metric #{storage_key}: #{error.message}")
      false
    end

    def definitions
      METRICS_CONFIG.each_with_object([]) do |(raw_key, raw_config), arr|
        metric_key = raw_key.to_sym
        metric_config = raw_config.respond_to?(:to_h) ? raw_config.to_h : {}
        arr << Definition.new(key: metric_key, config: metric_config)
      end
    end

    def definition_for(metric_key)
      normalized_key = metric_key.to_sym
      definition = definitions.find { |item| item.key == normalized_key }
      raise ArgumentError, "Unknown metric key: #{metric_key}" unless definition

      definition
    end

    def refreshable_definitions
      definitions.select(&:refreshable?).sort_by do |definition|
        LOCK_KEYS.index(definition.key) || LOCK_KEYS.length
      end
    end

    def admin_definitions
      definitions.select(&:show_in_admin?).sort_by do |definition|
        LOCK_KEYS.index(definition.key) || LOCK_KEYS.length
      end
    end

    def writer_method_for(metric_key)
      method_name = definition_for(metric_key).writer_method
      return method_name if respond_to?(method_name)

      raise ArgumentError, "Unknown metric key: #{metric_key}"
    end

    def write_datasets_tsv
      metric_key = :datasets_tsv
      set_in_progress(metric_key)

      begin
        headings = %w[
          doi
          ingest_date
          release_date
          num_files
          num_bytes
          total_downloads
          num_relationships
          num_creators
          subject
          citation_text
        ]

        File.open(metric_path(metric_key), "w") do |file|
          file.puts(headings.join("\t"))

          Dataset.publicly_readable_now.includes(:datafiles, :related_materials, :creators).find_each do |dataset|
            values = [
              dataset.identifier.to_s,
              dataset.created_at&.to_date&.iso8601.to_s,
              dataset.release_date&.iso8601.to_s,
              dataset.datafiles.count.to_s,
              dataset.datafiles.sum(:binary_size).to_s,
              dataset.total_downloads.to_s,
              non_version_relationship_count(dataset).to_s,
              dataset.creators.count.to_s,
              dataset.subject.to_s,
              dataset.plain_text_citation
            ]

            file.puts(values.join("\t"))
          end
        end
      ensure
        clear_in_progress(metric_key)
      end
    end

    def write_dataset_downloads_csv
      write_dataset_downloads_csv_orchestrator
    end

    def write_datafile_downloads_csv
      write_datafile_downloads_csv_orchestrator
    end

    def write_dataset_downloads_csv_orchestrator
      write_dataset_downloads_csv_by_year(current_calendar_year, :calendar)
      write_dataset_downloads_csv_by_year(current_fiscal_year, :fiscal)
    end

    def write_datafile_downloads_csv_orchestrator
      write_datafile_downloads_csv_by_year(current_calendar_year, :calendar)
      write_datafile_downloads_csv_by_year(current_fiscal_year, :fiscal)
    end

    def write_dataset_downloads_csv_by_year(year, slice_type)
      target_filename = filename_for_year_metric(:dataset_downloads, year, slice_type)
      target_path = Rails.root.join("public", target_filename)

      mark_year_metric_in_progress(:dataset_downloads, year, slice_type)
      begin
        public_keys = download_metrics_public_dataset_keys
        scope = DatasetDownloadTally.where(dataset_key: public_keys)
        scope = apply_download_year_filter(scope, year, slice_type)

        CSV.open(target_path, "w") do |report|
          report << DATASET_DOWNLOADS_CSV_HEADINGS
          scope.find_each do |row|
            report << [ row.dataset_key, row.doi, row.download_date, row.tally ]
          end
        end

        handle_archived_metric(target_path, :dataset_downloads, year, slice_type)
      ensure
        clear_year_metric_in_progress(:dataset_downloads, year, slice_type)
      end
    end

    def write_datafile_downloads_csv_by_year(year, slice_type)
      target_filename = filename_for_year_metric(:datafile_downloads, year, slice_type)
      target_path = Rails.root.join("public", target_filename)

      mark_year_metric_in_progress(:datafile_downloads, year, slice_type)
      begin
        public_keys = download_metrics_public_dataset_keys
        scope = FileDownloadTally.where(dataset_key: public_keys)
        scope = apply_download_year_filter(scope, year, slice_type)

        CSV.open(target_path, "w") do |report|
          report << DATAFILE_DOWNLOADS_CSV_HEADINGS
          scope.find_each do |row|
            report << [ row.file_web_id, row.dataset_key, row.doi, row.download_date, row.tally ]
          end
        end

        handle_archived_metric(target_path, :datafile_downloads, year, slice_type)
      ensure
        clear_year_metric_in_progress(:datafile_downloads, year, slice_type)
      end
    end

    def write_datafiles_csv
      metric_key = :datafiles_csv
      set_in_progress(metric_key)

      begin
        File.open(metric_path(metric_key), "w") do |file|
          CSV.open(file, "w") do |csv|
            csv << %w[doi pub_date filename file_format num_bytes total_downloads]

            Dataset.publicly_readable_now.includes(:datafiles).find_each do |dataset|
              dataset.datafiles.each do |datafile|
                csv << [
                  dataset.identifier.to_s,
                  dataset.release_date&.iso8601.to_s,
                  datafile.binary_name.to_s,
                  content_type_for(datafile),
                  datafile.binary_size.to_i,
                  datafile.total_downloads.to_i
                ]
              end
            end
          end
        end
      ensure
        clear_in_progress(metric_key)
      end
    end

    def write_container_contents_csv
      metric_key = :container_contents_csv
      set_in_progress(metric_key)

      begin
        File.open(metric_path(metric_key), "w") do |file|
          CSV.open(file, "w") do |csv|
            csv << %w[doi container_filename content_filepath content_filename file_format]

            Dataset.publicly_readable_now.includes(:datafiles).find_each do |dataset|
              dataset.datafiles.each do |datafile|
                next unless datafile.respond_to?(:nested_items)
                next unless datafile.respond_to?(:archive?) && datafile.archive?

                datafile.nested_items.each do |item|
                  csv << [
                    dataset.identifier.to_s,
                    datafile.binary_name.to_s,
                    item.item_path,
                    item.item_name,
                    item.media_type
                  ]
                end
              end
            end
          end
        end
      ensure
        clear_in_progress(metric_key)
      end
    end

    def write_funders_csv
      metric_key = :funders_csv
      set_in_progress(metric_key)

      begin
        File.open(metric_path(metric_key), "w") do |file|
          CSV.open(file, "w") do |csv|
            csv << %w[doi funder grant]

            Dataset.publicly_readable_now.includes(:funders).find_each do |dataset|
              dataset.funders.each do |funder|
                csv << [ dataset.identifier, funder.name, funder.grant.presence || funder.award_number ]
              end
            end
          end
        end
      ensure
        clear_in_progress(metric_key)
      end
    end

    def write_related_materials_csv
      metric_key = :related_materials_csv
      set_in_progress(metric_key)

      begin
        File.open(metric_path(metric_key), "w") do |file|
          CSV.open(file, "w") do |csv|
            csv << %w[doi datacite_relationship material_id_type material_id material_type]

            Dataset.publicly_readable_now.includes(:related_materials).find_each do |dataset|
              dataset.related_materials.each do |material|
                relationships = material.datacite_list.to_s.split(",").map(&:strip).reject(&:blank?)
                relationships = [ material.relation_type.to_s.strip ] if relationships.empty?

                relationships.each do |relationship|
                  next if [ RelatedMaterial::VERSION_PREVIOUS_RELATION, RelatedMaterial::VERSION_NEW_RELATION ].include?(relationship)

                  csv << [
                    dataset.identifier.to_s,
                    relationship,
                    material.uri_type.to_s,
                    material.uri.to_s,
                    material.selected_type.presence || material.material_type.to_s
                  ]
                end
              end
            end
          end
        end
      ensure
        clear_in_progress(metric_key)
      end
    end

    def generate_datasets_reports
      csv_target_path = METRICS_CONFIG[:dataset_report_csv][:relative_path].to_s
      text_target_path = METRICS_CONFIG[:dataset_report_text][:relative_path].to_s

      File.open(csv_target_path, "w") do |csv_file|
        File.open(text_target_path, "w") do |text_file|
          CSV.open(csv_file, "w") do |report|
            report << %w[key doi release_date funders title keywords corresponding_creator subject]

            Dataset.publicly_readable_now.includes(:funders).find_each do |dataset|
              report << [
                dataset.key,
                dataset.identifier,
                dataset.release_date&.iso8601.to_s,
                dataset.funders.map { |f| "#{f.name} (#{f.grant.presence || f.award_number})" }.join("; "),
                dataset.title,
                dataset.keywords,
                [ dataset.corresponding_creator_name, dataset.corresponding_creator_email ].reject(&:blank?).join(" | "),
                dataset.subject
              ]

              text_file.puts("Key: #{dataset.key}")
              text_file.puts("Citation: #{dataset.plain_text_citation}")
              text_file.puts("Description: #{dataset.description}")
              text_file.puts("----------------------------------------\n\n")
            end
          end
        end
      end
    end

    def retrieve_archived_metric_from_storage(metric_type, year, slice_type)
      storage_key = storage_key_for_archived_metric(metric_type, year, slice_type)
      report_root = StorageManager.instance.report_root
      return nil unless report_root.exist?(storage_key)

      report_root.with_input_io(storage_key) do |io|
        return io.read
      end
    rescue StandardError => error
      Rails.logger.error("Error retrieving archived metric #{storage_key}: #{error.message}")
      nil
    end

    def build_zip_for_group(group)
      normalized_group = group.to_sym
      raise ArgumentError, "Invalid group: #{group}" unless DOWNLOAD_ZIP_GROUPS.include?(normalized_group)

      metric_type, slice_type = normalized_group.to_s.split("_").then { |metric, slice| [ "#{metric}_downloads".to_sym, slice.to_sym ] }
      current_year = slice_type == :fiscal ? current_fiscal_year : current_calendar_year
      first_year = slice_type == :fiscal ? FIRST_DOWNLOAD_FISCAL_YEAR : FIRST_DOWNLOAD_CALENDAR_YEAR

      require "zip"
      buffer = Zip::OutputStream.write_buffer do |zip|
        add_current_year_metric_to_zip(zip, metric_type, current_year, slice_type)

        (first_year...current_year).to_a.reverse_each do |year|
          content = retrieve_archived_metric_from_storage(metric_type, year, slice_type)
          next if content.blank?

          zip.put_next_entry(filename_for_year_metric(metric_type, year, slice_type))
          zip.write(content)
        end
      end

      buffer.string
    end

    def archive_prior_year_downloads_to_storage
      current_cal_year = current_calendar_year
      current_fis_year = current_fiscal_year

      %i[dataset_downloads datafile_downloads].each do |metric_type|
        (FIRST_DOWNLOAD_CALENDAR_YEAR...current_cal_year).each do |year|
          maybe_archive_metric_file(metric_type, year, :calendar)
        end

        (FIRST_DOWNLOAD_FISCAL_YEAR...current_fis_year).each do |year|
          maybe_archive_metric_file(metric_type, year, :fiscal)
        end
      end
    end

    def generate_all_historical_downloads
      current_cal_year = current_calendar_year
      current_fis_year = current_fiscal_year

      %i[dataset_downloads datafile_downloads].each do |metric_type|
        (FIRST_DOWNLOAD_CALENDAR_YEAR...current_cal_year).each do |year|
          public_send("write_#{metric_type}_csv_by_year", year, :calendar)
        end

        (FIRST_DOWNLOAD_FISCAL_YEAR...current_fis_year).each do |year|
          public_send("write_#{metric_type}_csv_by_year", year, :fiscal)
        end
      end
    end

    private

    def add_current_year_metric_to_zip(zip, metric_type, current_year, slice_type)
      filename = filename_for_year_metric(metric_type, current_year, slice_type)
      path = Rails.root.join("public", filename)
      return unless File.exist?(path)

      zip.put_next_entry(filename)
      zip.write(File.read(path))
    end

    def maybe_archive_metric_file(metric_type, year, slice_type)
      filename = filename_for_year_metric(metric_type, year, slice_type)
      file_path = Rails.root.join("public", filename)
      return unless File.exist?(file_path)

      archive_metric_to_storage(file_path, metric_type, year, slice_type)
    end

    def apply_download_year_filter(scope, year, slice_type)
      return scope.where("EXTRACT(YEAR FROM download_date) = ?", year) if slice_type == :calendar

      start_date, end_date = date_range_for_fiscal_year(year)
      scope.where(download_date: start_date..end_date)
    end

    def year_metric_lock_path(metric_type, year, slice_type)
      filename = filename_for_year_metric(metric_type, year, slice_type)
      Rails.root.join("public", "#{filename}.lock")
    end

    def mark_year_metric_in_progress(metric_type, year, slice_type)
      FileUtils.touch(year_metric_lock_path(metric_type, year, slice_type))
    end

    def clear_year_metric_in_progress(metric_type, year, slice_type)
      lock_path = year_metric_lock_path(metric_type, year, slice_type)
      File.delete(lock_path) if File.exist?(lock_path)
    end

    def should_archive_metric?(year, slice_type)
      !year_is_current?(year, slice_type)
    end

    def handle_archived_metric(file_path, metric_type, year, slice_type)
      return nil unless should_archive_metric?(year, slice_type)

      archive_metric_to_storage(file_path, metric_type, year, slice_type)
    end

    def archive_metric_to_storage(file_path, metric_type, year, slice_type)
      return nil unless File.exist?(file_path)

      storage_key = storage_key_for_archived_metric(metric_type, year, slice_type)
      report_root = StorageManager.instance.report_root
      file_content = File.read(file_path)
      report_root.copy_io_to(storage_key, StringIO.new(file_content), nil, file_content.bytesize)
      File.delete(file_path)
      storage_key
    end

    def ensure_metrics_exist!
      refreshable_definitions.each do |definition|
        ensure_metric_file_present(definition)
      end
    end

    def ensure_metric_file_present(definition)
      return if File.exist?(definition.relative_path)

      public_send(writer_method_for(definition.key))
      return if File.exist?(definition.relative_path)

      raise StandardError, "unable to create #{definition.label}"
    end

    def metric_path(metric_key)
      definition_for(metric_key).relative_path
    end

    def format_mtime(metric_key)
      path = metric_path(metric_key)
      return "not found" unless File.exist?(path)

      File.mtime(path).to_fs(:long)
    end

    def non_version_relationship_count(dataset)
      dataset.related_materials.count do |material|
        !material.version_relation?
      end
    end

    def content_type_for(datafile)
      if datafile.binary.attached?
        datafile.binary.content_type.to_s.presence || "application/octet-stream"
      elsif datafile.binary_name.present?
        Marcel::MimeType.for(name: datafile.binary_name).to_s
      else
        "application/octet-stream"
      end
    rescue StandardError
      "application/octet-stream"
    end

    def download_metrics_public_dataset_keys
      Dataset.files_publicly_readable_now_scope.pluck(:key)
    end
  end
end
