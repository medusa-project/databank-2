# frozen_string_literal: true

##
# Encapsulates client functionality for the Medusa downloader service

require "json"
require "curb"

class DownloaderClient
  include ActiveModel::Conversion
  include ActiveModel::Naming

  # all methods are class methods
  class << self
    ##
    # @param dataset [Dataset] The dataset the files belong to
    # @param web_ids [Array] The web_ids of the files to download
    # @param zip_name [String] The name of the zip file to create
    def datafiles_download_hash(dataset:, web_ids:, zip_name:)
      begin
        targets_arr = targets_arr(dataset: dataset, web_ids: web_ids)
        unless targets_arr.count.positive?
          Rails.logger.warn "error in datafiles_download_hash for dataset #{dataset.id} and web_ids #{web_ids}"
          return { "status": "error", "error": "internal error no valid files found" }
        end
      rescue StandardError => e
        Rails.logger.warn "error in datafiles_download_hash: #{e.message}"
        return { "status": "error", "error": "internal error file path not found" }
      end

      medusa_request_json = { "root": "idb", "zip_name": zip_name.to_s, "targets": targets_arr }.to_json
      download_hash = request_download_hash(medusa_request_json: medusa_request_json)
      download_hash[:total_size] = total_size(dataset: dataset, web_ids: web_ids) if download_hash[:status] == "ok"
      download_hash
    end

    private

    ##
    # @param dataset [Dataset] The dataset the files belong to
    # @param web_ids [Array] The web_ids of the files to download
    # @return [Array] The array of files to download
    def targets_arr(dataset:, web_ids:)
      targets_arr = []
      web_ids.each do |web_id|
        df = dataset.datafiles.find_by(web_id: web_id)
        next unless df

        if df.binary.attached?
          # For ActiveStorage attachments, use the storage key if available
          targets_arr.push({ "type": "file", "path": (df.storage_key.presence || df.web_id) })
        elsif df.storage_key.present?
          # For Medusa-backed files
          targets_arr.push({ "type": "file", "path": df.storage_key.to_s })
        end
      end
      targets_arr.push({ "type": "literal", "name": "dataset_info.txt", "content": dataset.record_text })
      targets_arr
    end

    ##
    # @param medusa_request_json [String] The JSON string to send to the downloader
    # @return [Hash] The response hash from the downloader
    # @note: This method sends a request to the downloader to download the files
    def request_download_hash(medusa_request_json:)
      user = Rails.application.credentials.dig(:downloader, :user)
      password = Rails.application.credentials.dig(:downloader, :password)
      endpoint = Rails.application.credentials.dig(:downloader, :endpoint)

      unless endpoint && user && password
        Rails.logger.warn "downloader credentials not configured"
        return { "status": "error", "error": "downloader service not configured" }
      end

      client = Curl::Easy.new(endpoint.to_s)
      client.http_auth_types = :digest
      client.ssl_verify_peer = true
      client.username = user
      client.password = password
      client.post_body = medusa_request_json
      client.headers = { "Content-Type": "application/json" }
      client.post
      client.perform

      response_hash = JSON.parse(client.body_str)
      unless response_hash.key?("download_url")
        return { "status": "error", "error": "invalid response from downloader service" }
      end

      { "status": "ok", "download_url": response_hash["download_url"], "status_url": response_hash["status_url"] }
    rescue StandardError => e
      Rails.logger.warn "error interacting with medusa-downloader: #{e.class} #{e.message}"
      { "status": "error", "error": "internal error downloading files" }
    end

    ##
    # @param dataset [Dataset] The dataset containing the datafiles to download
    # @param web_ids [Array] The array of web_ids for datafiles to download
    # @return [Integer] The total size of the files to download
    def total_size(dataset:, web_ids:)
      total_size = 0
      web_ids.each do |web_id|
        df = Datafile.find_by(web_id: web_id)
        next unless df

        file_size = if df.binary.attached?
                      df.binary.byte_size
        else
                      df.binary_size.to_i
        end
        total_size += file_size
      end
      total_size += dataset.record_text.bytesize
    end
  end
end
