class Dataset < ApplicationRecord
  include Dataset::IllinoisExpertsExportable
  include Dataset::Globusable
  include Dataset::Versionable
  include Dataset::Publishable
  include Dataset::Searchable

  class << self
    def citation_report(datasets:, request_url:, current_user:)
      report_text = String.new

      15.times { report_text << "=" }
      report_text << "\nIllinois Data Bank\nDatasets Report, generated #{Date.current.iso8601}"
      report_text << " by #{current_user.username}" if current_user&.username.present?
      report_text << "\nQuery URL: #{request_url}\n"
      15.times { report_text << "=" }
      report_text << "\n"

      datasets.each do |dataset|
        report_text << "\n\n#{dataset.plain_text_citation}"

        if dataset.funders.any?
          dataset.funders.each do |funder|
            report_text << "\nFunder: #{funder.name}"
            grant_value = funder.grant.presence || funder.award_number
            report_text << ", Grant: #{grant_value}" if grant_value.present?
          end
        end

        start_time = (dataset.published_at || dataset.updated_at || dataset.created_at)&.to_date&.iso8601 || Date.current.iso8601
        report_text << "\nDownloads: #{dataset.total_downloads} (#{start_time} to #{Date.current.iso8601} )\n"
        5.times { report_text << "-" }
      end

      report_text
    end

    private
  end

  KEY_PREFIX = IdbConfig.fetch(:dataset, :key_prefix, default: "IDB").freeze
  KEY_DIGITS = 7
  CREATOR_TYPE_PERSON = 0
  CREATOR_TYPE_INSTITUTION = 1

  audited except: %i[
    creator_text
    key
    complete
    is_test
    is_import
    updated_at
    nested_updated_at
  ]
  has_associated_audits

  has_many :datafiles,         dependent: :destroy
  has_many :dataset_access_grants, -> { order(:email, :access_level) }, dependent: :destroy
  has_many :creators,          -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :contributors,      -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :funders,           -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_many :notes,             -> { order(created_at: :desc, id: :desc) }, dependent: :destroy
  has_many :related_materials, -> { order(Arel.sql("COALESCE(row_position, position) ASC, id ASC")) }, dependent: :destroy
  has_one :token, class_name: "Token", primary_key: :key, foreign_key: :dataset_key, inverse_of: :dataset, dependent: :destroy
  has_many :review_requests, dependent: :destroy
  has_many :external_delivery_attempts, dependent: :destroy

  accepts_nested_attributes_for :datafiles, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :creators, reject_if: :invalid_name, allow_destroy: true
  accepts_nested_attributes_for :contributors, reject_if: :invalid_name, allow_destroy: true
  accepts_nested_attributes_for :funders,
                                reject_if: proc { |attributes| attributes["name"].blank? },
                                allow_destroy: true
  accepts_nested_attributes_for :related_materials, reject_if: :invalid_material, allow_destroy: true

  validates :key,             presence: true, uniqueness: true
  validates :owner_uid,       presence: true
  validates :depositor_name,  presence: true
  validates :depositor_email, presence: true

  before_validation :set_key, on: :create
  before_save :set_primary_contact

  def to_param
    key
  end

  def generate_doi
    "10.5555/#{key}"
  end

  def persistent_url
    return if identifier.blank?

    "https://doi.org/#{identifier}"
  end

  def creators_citation_format
    creator_names = creators.map { |c| format_creator_for_citation(c) }.reject(&:blank?)
    return "[Creators Not Yet Added]" if creator_names.empty?
    return creator_names.first if creator_names.size == 1
    return "#{creator_names[0]} & #{creator_names[1]}" if creator_names.size == 2

    # 3+ creators: "First, Second, & Third"
    "#{creator_names[0..-2].join(", ")} & #{creator_names[-1]}"
  end

  def format_creator_for_citation(creator)
    # Institution creators: use institution_name only
    return creator.institution_name if creator.institution_name.present?

    # Individual creators: format as "Family, Given"
    return nil if creator.family_name.blank?

    given_name = creator.given_name.to_s.strip
    return creator.family_name if given_name.blank?

    "#{creator.family_name}, #{given_name}"
  end

  def citation_minus_title
    citation_parts = []
    citation_parts << creators_citation_format

    year = published_at&.year || updated_at&.year || created_at&.year
    citation_parts << "(#{year})." if year.present?
    citation_parts << publisher if publisher.present?
    citation_parts << "https://doi.org/#{identifier}" if identifier.present?

    citation_parts.join(" ")
  end

  def citation_with_title
    return citation_minus_title if title.blank?

    citation_parts = []
    citation_parts << creators_citation_format

    year = published_at&.year || updated_at&.year || created_at&.year
    citation_parts << "(#{year})." if year.present?

    citation_parts << "*#{title}* (Version 1.0)"
    citation_parts << "[Data set]."
    citation_parts << publisher if publisher.present?
    citation_parts << "https://doi.org/#{identifier}" if identifier.present?

    citation_parts.join(" ")
  end

  def plain_text_citation
    citation_with_title
  end


  def individual_creators
    creators.select { |creator| creator.type_of != CREATOR_TYPE_INSTITUTION }
  end

  def institutional_creators
    creators.select { |creator| creator.type_of == CREATOR_TYPE_INSTITUTION }
  end

  def prune_creators_for_mode!(org_mode:)
    if org_mode
      creators.where(type_of: [ nil, CREATOR_TYPE_PERSON ]).destroy_all
      creators.where(type_of: CREATOR_TYPE_INSTITUTION).update_all(type_of: CREATOR_TYPE_INSTITUTION)
    else
      creators.where(type_of: CREATOR_TYPE_INSTITUTION).destroy_all
      creators.where(type_of: [ nil, CREATOR_TYPE_PERSON ]).update_all(type_of: CREATOR_TYPE_PERSON)
    end
  end

  def curator_ingested_date
    attempts = if association(:external_delivery_attempts).loaded?
                 external_delivery_attempts.select { |attempt| attempt.integration == "ingest" && attempt.status == "succeeded" }
    else
                 external_delivery_attempts.where(integration: :ingest, status: :succeeded)
    end

    latest_attempt = if attempts.respond_to?(:order)
                       attempts.order(response_received_at: :desc, created_at: :desc).first
    else
                       attempts.max_by { |attempt| attempt.response_received_at || attempt.created_at }
    end

    (latest_attempt&.response_received_at || latest_attempt&.created_at)&.to_date
  end

  def has_sharing_link?
    token.present?
  end

  def record_text
    return "Method not valid for draft dataset." if identifier.blank?

    content = "##########################################################################################\n"
    content += "#  About this file:\n"
    content += "#  The dataset described in this info file was downloaded in part or in whole\n"
    content += "#  from the Illinois Data Bank.\n"
    content += "#  This info file contains citation information, a permanent digital object identifier (DOI),\n"
    content += "#  and a listing of all data files available for this dataset.\n"
    content += "#  Keep this info file so in the future you'll know where you obtained\n"
    content += "#  the data files you've just downloaded.\n"
    content += "##########################################################################################\n\n"

    content += "[ DOI: ] #{identifier}\n"
    content += "[ Title: ] #{title}\n"
    content += "[ #{'Creator'.pluralize(creators.count)}: ] #{creator_names_for_record_text}\n"
    content += "[ Publisher: ] #{publisher}\n"
    content += "[ Publication Year: ] #{publication_year_for_record_text}\n\n"
    content += "[ Citation: ] #{plain_text_citation}\n\n"

    content += "[ Description: ] #{description}\n\n" if description.present?
    content += "[ Keywords: ] #{keywords}\n" if keywords.present?

    content += "[ License: ] #{license_line_for_record_text}\n"
    content += "[ Corresponding Creator: ] #{corresponding_creator_name}\n"

    if funders.any?
      funders.each do |funder|
        content += "[ Funder: ] #{funder.name}"
        grant_value = funder.grant.presence || funder.award_number
        content += " - [ Grant: ] #{grant_value}" if grant_value.present?
        content += "\n"
      end
      content += "\n"
    end

    if related_materials.any?
      related_materials.each do |material|
        next if material.version_relation?
        next unless material.citation.present? || material.link.present? || material.uri.present?

        label = material.material_type.presence || "Material"
        parts = [ material.citation.presence, material.link.presence, material.uri.presence ].compact
        content += "[ Related #{label}: ] #{parts.join(', ')}\n"
      end
    end

    file_count = datafiles.size
    content += "\n[ #{'File'.pluralize(file_count)} (#{file_count}): ]\n"
    datafiles.order(:id).each do |datafile|
      formatted_size = ActionController::Base.helpers.number_to_human_size(datafile.binary_size.to_i)
      content += ". #{datafile.binary_name}, #{formatted_size}\n"
    end

    content
  end

  def today_downloads
    DayFileDownload.where(dataset_key: key, download_date: Date.current).distinct.count(:ip_address)
  end

  def total_downloads
    DatasetDownloadTally.where(dataset_key: key).sum(:tally)
  end

  def dataset_download_tallies
    DatasetDownloadTally.where(dataset_key: key)
  end

  def ip_downloaded_dataset_today(request_ip)
    DayFileDownload.where(
      ip_address: request_ip,
      dataset_key: key,
      download_date: Date.current
    ).exists?
  end

  def current_token
    token
  end

  def new_token
    token&.destroy!
    create_token!(identifier: Token.generate_auth_token)
  end

  def creator_list
    creator_display_names(separator: "; ")
  end

  def bibtex_creator_list
    creator_display_names(separator: " and ")
  end

  def publication_year
    release_date&.year
  end

  private

  def creator_display_names(separator:)
    creators.map(&:display_name).map(&:to_s).map(&:strip).reject(&:blank?).join(separator)
  end

  def creator_names_for_record_text
    names = creators.map(&:name).reject(&:blank?)
    return "[Creator List]" if names.empty?

    names.join("; ")
  end

  def publication_year_for_record_text
    (published_at || updated_at || created_at).year
  end

  def license_line_for_record_text
    case license.to_s
    when "CC01", "CC0"
      "CC0 - https://creativecommons.org/publicdomain/zero/1.0/"
    when "CCBY4", "CC-BY-4.0"
      "CC BY - https://creativecommons.org/licenses/by/4.0/"
    when "license.txt"
      "Custom - See license.txt file in dataset."
    else
      "Not found."
    end
  end

  def invalid_name(attributes)
    attributes["family_name"].blank? &&
      attributes["given_name"].blank? &&
      attributes["institution_name"].blank? &&
      attributes["name"].blank?
  end

  def invalid_material(attributes)
    attributes["link"].blank? && attributes["citation"].blank?
  end

  def set_primary_contact
    self.corresponding_creator_name = nil
    self.corresponding_creator_email = nil

    creators.to_a.each do |creator|
      next unless creator.contact_selected?

      self.corresponding_creator_name = creator.display_name
      self.corresponding_creator_email = creator.email
      break
    end
  end

  def set_key
    self.key ||= generate_key
  end

  def generate_key
    loop do
      candidate = "#{KEY_PREFIX}-#{rand(10**KEY_DIGITS).to_s.rjust(KEY_DIGITS, '0')}"
      break candidate unless self.class.exists?(key: candidate)
    end
  end
end
