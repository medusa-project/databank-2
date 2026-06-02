require "yaml"
require "erb"

config_path = Rails.root.join("config", "idb_config.yml")

unless File.exist?(config_path)
  raise "Missing required configuration file: #{config_path}"
end

raw_config = YAML.safe_load(ERB.new(File.read(config_path)).result, aliases: true) || {}
default_config = raw_config.fetch("default", {})
environment_config = raw_config.fetch(Rails.env, {})

merged_config = default_config.deep_merge(environment_config).deep_symbolize_keys

Object.send(:remove_const, :IDB_CONFIG) if defined?(IDB_CONFIG)
IDB_CONFIG = merged_config.with_indifferent_access
