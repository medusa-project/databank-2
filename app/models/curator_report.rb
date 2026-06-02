# frozen_string_literal: true

require "csv"
require "stringio"

class CuratorReport < ApplicationRecord
  FILE_AUDIT = "file_audit"
  REPORT_TYPES = [ FILE_AUDIT ].freeze

  before_destroy :destroy_report_file

  validates :requestor_name, :requestor_email, :report_type, presence: true
  validates :requestor_email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :report_type, inclusion: { in: REPORT_TYPES }

  class << self
    def initiate_report_generation(report_type:, requesting_user:, notes: nil, storage_root: default_storage_root)
      report = create!(
        report_type: report_type,
        requestor_name: requesting_user.name,
        requestor_email: requesting_user.email,
        storage_root: storage_root,
        notes: notes.presence
      )
      report.update!(storage_key: report.default_storage_key)

      CuratorReportJob.perform_later(report.id)
      report
    end

    def generate_report(report)
      case report.report_type
      when FILE_AUDIT
        generate_file_audit_report(report)
      else
        raise "Unknown report type: #{report.report_type}"
      end
    end

    def generate_file_audit_report(report)
      csv_string = CSV.generate do |csv|
        csv << [
          "File Name",
          "Storage Root",
          "File Size (bytes)",
          "File Status",
          "File URL",
          "Dataset Title",
          "Dataset URL",
          "Publication State"
        ]

        Dataset.includes(:datafiles).find_each do |dataset|
          dataset.datafiles.each do |file|
            file_status = file.exists_on_storage? ? "exists" : "missing"
            csv << [
              file.binary_name,
              file.storage_root,
              file.binary_size,
              file_status,
              file_download_url(dataset, file),
              dataset.title,
              dataset_url(dataset),
              dataset.publication_state
            ]
          end
        end
      end

      report.current_root.copy_io_to(report.storage_key, StringIO.new(csv_string), nil, csv_string.bytesize)
    end

    def default_storage_root
      StorageManager.instance.report_root.name
    end

    private

    def url_helpers
      Rails.application.routes.url_helpers
    end

    def root_url
      IdbConfig.fetch(:app, :root_url_text, default: "http://localhost:3000")
    end

    def dataset_url(dataset)
      url_helpers.dataset_url(dataset, host: root_url)
    end

    def file_download_url(dataset, datafile)
      url_helpers.download_dataset_datafile_url(dataset, datafile, host: root_url)
    end
  end

  def default_storage_key
    day = Time.current.strftime("%Y-%m-%d")
    time = Time.current.strftime("%H-%M-%S")
    "#{report_type}_report-#{id}_#{day}_#{time}.csv"
  end

  def download_link
    Rails.application.routes.url_helpers.download_curator_report_path(self)
  end

  def current_root
    StorageManager.instance.root_set.at(storage_root)
  end

  def status
    return "pending" if current_root.nil? || storage_key.blank? || storage_root.blank?

    if current_root.exist?(storage_key)
      "available"
    elsif created_at < 1.hour.ago
      "generating"
    else
      "pending"
    end
  end

  def status_label_class
    case status
    when "available" then "label-success"
    when "generating" then "label-warning"
    else "label-default"
    end
  end

  private

  def destroy_report_file
    return if current_root.nil? || storage_key.blank? || storage_root.blank?

    current_root.delete_content(storage_key) if current_root.exist?(storage_key)
    current_root.delete_content("#{storage_key}.info") if current_root.exist?("#{storage_key}.info")
  end
end
