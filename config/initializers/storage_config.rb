require "erb"
require "yaml"

storage_config_path = if Rails.env.production?
  Rails.root.join("config", "medusa-storage.yml")
else
  Rails.root.join("config", "medusa-storage-ci.yml")
end

raw = ERB.new(File.read(storage_config_path)).result
parsed = YAML.safe_load(raw, aliases: true, permitted_classes: [ Symbol ])

STORAGE_CONFIG = if Rails.env.production?
  parsed.fetch(Rails.env).deep_symbolize_keys
else
  parsed.deep_symbolize_keys
end
