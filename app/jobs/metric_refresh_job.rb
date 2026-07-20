class MetricRefreshJob < ApplicationJob
  queue_as :default

  def perform(metric_key)
    normalized_key = metric_key.to_sym
    method_name = Metric.writer_method_for(normalized_key)

    Metric.public_send(method_name)
  end
end
