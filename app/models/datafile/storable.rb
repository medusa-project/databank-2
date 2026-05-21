module Datafile::Storable
  extend ActiveSupport::Concern

  def current_root
    return nil if storage_root.blank?

    StorageManager.instance.root_set.at(storage_root)
  end

  def storage_key_with_prefix
    return nil if storage_key.blank?
    return storage_key unless current_root&.prefix

    "#{current_root.prefix}#{storage_key}"
  end

  def exists_on_storage?
    return false if storage_key.blank?
    return false unless current_root

    current_root.exist?(storage_key)
  end

  def with_input_io
    raise ArgumentError, "storage root not configured" unless current_root
    raise ArgumentError, "storage key missing" if storage_key.blank?

    current_root.with_input_io(storage_key) do |io|
      yield io
    end
  end
end
