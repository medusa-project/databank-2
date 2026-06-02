# frozen_string_literal: true

class CuratorReportJob < ApplicationJob
  queue_as :default

  def perform(curator_report_id)
    report = CuratorReport.find(curator_report_id)
    CuratorReport.generate_report(report)
  end
end
