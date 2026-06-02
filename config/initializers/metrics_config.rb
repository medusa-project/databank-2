require "erb"
require "yaml"

raw_metrics_config = ERB.new(File.read(Rails.root.join("config", "metrics.yml"))).result
parsed_metrics_config = YAML.safe_load(raw_metrics_config, aliases: true, permitted_classes: [ Symbol ])

METRICS_CONFIG = parsed_metrics_config.deep_symbolize_keys
