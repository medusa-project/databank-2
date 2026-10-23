module Dataset::Globusable
  extend ActiveSupport::Concern

  class Error < StandardError; end

  included do
    after_create :ensure_globus_ingest_dir, if: :globus_ingest_configured?
    before_destroy :remove_globus_storage, prepend: true
  end

  # Check if dataset files are preserved/available in the preservation system
  # Requires: published status + all datafiles switched to the Medusa storage root
  # (all_medusa is set by Medusa::FinalizeIngestService, avoiding a storage check on every page load)
  def fileset_preserved?
    return @fileset_preserved if defined?(@fileset_preserved)

    @fileset_preserved = published? && all_medusa?
  end

  # Check if dataset files are available via Globus download
  # Requires: published status + all datafiles copied to the Globus download root
  # (all_globus is set by Globus::PublicCopyService and cleared by Globus::SuppressionService)
  def globus_downloadable?
    files_publicly_readable_now? && all_globus?
  end

  def globus_download_dir
    globus_file_manager_url(:download_url_base)
  end

  def globus_ingest_dir
    globus_file_manager_url(:ingest_url_base)
  end

  def globus_ingest_configured?
    IdbConfig.fetch(:globus, :ingest_url_base).present?
  end

  def ensure_globus_ingest_dir
    root = StorageManager.instance.globus_ingest_root
    directory = "#{key}/"
    return true if root.exist?(directory)

    if root.root_type == :filesystem
      root.path_to(directory).mkpath
    else
      root.write_string_to(directory, "")
    end

    raise Error, "Unable to create Globus ingest directory" unless root.exist?(directory)

    true
  end

  def copy_to_globus_ingest_dir(source_root_name:, source_key:, target_name_override: nil)
    source_root = StorageManager.instance.root_set.at(source_root_name)
    raise Error, "Source file not found" unless source_root.exist?(source_key)

    name = target_name_override || File.basename(source_key)
    unless name.present? && File.basename(name) == name && !%w[. ..].include?(name)
      raise Error, "Invalid Globus ingest filename"
    end

    ensure_globus_ingest_dir
    StorageManager.instance.globus_ingest_root.copy_content_to("#{key}/#{name}", source_root, source_key)
  end

  def import_from_globus
    root = StorageManager.instance.globus_ingest_root
    unless root.exist?("#{key}/") || (root.root_type == :s3 && root.file_keys(key).any?)
      raise Error, "Files not found on Globus endpoint"
    end

    Globus::IngestImportService.new(dataset_key: key).call
  end

  def too_big?
    limit = Float(IdbConfig.fetch(:globus, :only_gb, default: 2))
    raise Error, "globus.only_gb must be a positive finite number" unless limit.finite? && limit.positive?

    datafiles.sum(:binary_size) > limit * (2**30)
  rescue ArgumentError, TypeError
    raise Error, "globus.only_gb must be a positive finite number"
  end

  def delete_from_globus_ingest_dir(storage_key:)
    target_key = storage_key.start_with?("#{key}/") ? storage_key : "#{key}/#{storage_key}"
    relative_key = target_key.delete_prefix("#{key}/")
    if relative_key.blank? || relative_key.split("/").any? { |part| part.blank? || %w[. ..].include?(part) }
      raise Error, "Invalid Globus ingest key"
    end

    ensure_globus_file_unreferenced!(target_key)
    root = StorageManager.instance.globus_ingest_root
    root.delete_content(target_key) if root.exist?(target_key)
    true
  end

  def remove_globus_ingest_dir
    root = StorageManager.instance.globus_ingest_root
    directory = "#{key}/"
    directory_exists = root.exist?(directory)
    return true unless directory_exists || root.root_type == :s3

    storage_keys = root.file_keys(key)
    storage_keys.each { |storage_key| ensure_globus_file_unreferenced!(storage_key) }
    storage_keys.each { |storage_key| root.delete_content(storage_key) }
    if root.root_type == :filesystem
      root.path_to(directory).rmdir
    elsif directory_exists
      root.delete_content(directory)
    end
    true
  end

  def remove_from_globus_download
    Globus::SuppressionService.new(self).remove_from_public_download
  end

  # Check if dataset has external files (files not in the repository system)
  def external_files?
    external_files_note.to_s.strip.present? || external_files_link.to_s.strip.present?
  end

  private

  def globus_file_manager_url(config_key)
    base = IdbConfig.fetch(:globus, config_key).to_s.strip
    uri = URI.parse(base)
    unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
      raise Error, "Configure globus.#{config_key} with an HTTPS Globus File Manager URL"
    end

    query = URI.decode_www_form(uri.query.to_s).to_h
    unless query["origin_id"].present? && query["origin_path"]&.start_with?("/")
      raise Error, "Globus File Manager URL requires origin_id and an absolute origin_path"
    end

    query["origin_path"] = "#{query.fetch("origin_path").delete_suffix("/")}/#{key}"
    uri.query = URI.encode_www_form(query)
    uri.to_s
  rescue URI::InvalidURIError, ArgumentError => e
    raise Error, "Invalid Globus File Manager URL: #{e.message}"
  end

  def ensure_globus_file_unreferenced!(storage_key)
    if Datafile.where.not(dataset_id: id).where(storage_root: %w[draft globus_ingest], storage_key: storage_key).exists?
      raise Error, "Globus ingest file is still referenced by another dataset: #{storage_key}"
    end
  end

  def remove_globus_storage
    remove_globus_ingest_dir if globus_ingest_configured?
    if all_globus? || IdbConfig.fetch(:globus, :download_url_base).present?
      raise Error, "Unable to remove files from Globus download" unless remove_from_globus_download
    end
  end
end
