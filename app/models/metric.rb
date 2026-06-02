# frozen_string_literal: true

require "csv"
require "fileutils"

class Metric
  LOCK_KEYS = %i[
    dataset_downloads_json
    datafile_downloads_json
    datasets_tsv
    datafiles_csv
    container_contents_csv
    funders_csv
    related_materials_csv
  ].freeze

  class << self
    def refresh_all
      write_dataset_downloads_json
      write_datafile_downloads_json
      write_datafiles_csv
      write_datasets_tsv
      write_container_contents_csv
      write_funders_csv
      write_related_materials_csv
    end

    def lock_path(metric_key)
      "#{metric_path(metric_key)}.lock"
    end

    def in_progress?(metric_key)
      File.exist?(lock_path(metric_key))
    end

    def refresh_status
      LOCK_KEYS.each_with_object({}) { |key, hash| hash[key] = in_progress?(key) }
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

      {
        dataset_downloads_json: format_mtime(:dataset_downloads_json),
        datafile_downloads_json: format_mtime(:datafile_downloads_json),
        datafiles_csv: format_mtime(:datafiles_csv),
        datasets_tsv: format_mtime(:datasets_tsv),
        container_contents_csv: format_mtime(:container_contents_csv),
        funders_csv: format_mtime(:funders_csv),
        related_materials_csv: format_mtime(:related_materials_csv)
      }
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
              plain_text_citation(dataset)
            ]

            file.puts(values.join("\t"))
          end
        end
      ensure
        clear_in_progress(metric_key)
      end
    end

    def write_dataset_downloads_json
      metric_key = :dataset_downloads_json
      set_in_progress(metric_key)

      begin
        first_record = true
        totals = Hash.new(0)

        File.open(metric_path(metric_key), "w") do |file|
          file.puts(%({"dataset_downloads":[))

          DatasetDownloadTally.order(:download_date, :id).find_each do |row|
            row_json = { doi: row.doi, date: row.download_date, tally: row.tally }.to_json
            file.puts(first_record ? row_json : ",#{row_json}")
            first_record = false
            totals[row.doi] += row.tally.to_i if row.doi.present?
          end

          file.puts("]}")
        end

        totals_path = metric_path(metric_key).sub(/\.json\z/, "_totals.csv")
        File.open(totals_path, "w") do |file|
          file.puts("doi,tally")
          totals.each { |doi, tally| file.puts("#{doi},#{tally}") }
        end
      ensure
        clear_in_progress(metric_key)
      end
    end

    def write_datafile_downloads_json
      metric_key = :datafile_downloads_json
      set_in_progress(metric_key)

      begin
        first_record = true

        File.open(metric_path(metric_key), "w") do |file|
          file.puts(%({"datafile_downloads":[))

          FileDownloadTally.order(:download_date, :id).find_each do |row|
            row_json = {
              doi: row.doi,
              file: row.filename,
              date: row.download_date,
              tally: row.tally
            }.to_json
            file.puts(first_record ? row_json : ",#{row_json}")
            first_record = false
          end

          file.puts("]}")
        end
      ensure
        clear_in_progress(metric_key)
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
              text_file.puts("Citation: #{plain_text_citation(dataset)}")
              text_file.puts("Description: #{dataset.description}")
              text_file.puts("----------------------------------------\n\n")
            end
          end
        end
      end
    end

    private

    def ensure_metrics_exist!
      LOCK_KEYS.each do |metric_key|
        next if File.exist?(metric_path(metric_key))

        write_method_for(metric_key)
      end
    end

    def write_method_for(metric_key)
      case metric_key
      when :dataset_downloads_json then write_dataset_downloads_json
      when :datafile_downloads_json then write_datafile_downloads_json
      when :datasets_tsv then write_datasets_tsv
      when :datafiles_csv then write_datafiles_csv
      when :container_contents_csv then write_container_contents_csv
      when :funders_csv then write_funders_csv
      when :related_materials_csv then write_related_materials_csv
      else
        raise ArgumentError, "Unknown metric key: #{metric_key}"
      end
    end

    def metric_path(metric_key)
      METRICS_CONFIG.fetch(metric_key).fetch(:relative_path).to_s
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

    def plain_text_citation(dataset)
      citation_parts = []
      creator_names = dataset.creators.map(&:name).reject(&:blank?)

      citation_parts << creator_names.join("; ") if creator_names.any?
      year = dataset.published_at&.year || dataset.updated_at&.year || dataset.created_at&.year
      citation_parts << "(#{year})" if year.present?
      citation_parts << "#{dataset.title}." if dataset.title.present?
      citation_parts << dataset.publisher if dataset.publisher.present?
      citation_parts << "https://doi.org/#{dataset.identifier}" if dataset.identifier.present?

      citation_parts.join(" ")
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
  end
end
