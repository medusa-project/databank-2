require "singleton"

class StorageManager
  include Singleton

  attr_accessor :draft_root,
                :report_root,
                :medusa_root,
                :message_root,
                :tmpfs_root,
                :globus_download_root,
                :globus_ingest_root,
                :root_set,
                :tmpdir

  def initialize
    storage_config = STORAGE_CONFIG.fetch(:storage).map(&:to_h)
    self.root_set = MedusaStorage::RootSet.new(storage_config)
    self.draft_root = root_set.at("draft")
    self.report_root = root_set.at("reports")
    self.medusa_root = root_set.at("medusa")
    self.message_root = root_set.at("message")
    self.tmpfs_root = root_set.at("tmpfs")
    self.globus_download_root = root_set.at("globus_download")
    self.globus_ingest_root = root_set.at("globus_ingest")
    self.tmpdir = IdbConfig.fetch(:storage, :tmpdir, default: Dir.tmpdir)
  end

  def globus_ingest_uses_draft_storage?
    configs = STORAGE_CONFIG.fetch(:storage).index_by { |root| root.fetch(:name).to_s }
    configs.fetch("draft").except(:name) == configs.fetch("globus_ingest").except(:name)
  end
end
