require "json"

module Migration
  class RunReportWriter
    def initialize(report_path:, report:)
      @report_path = Pathname(report_path)
      @report = report
    end

    def call
      report_path.dirname.mkpath
      File.write(report_path, JSON.pretty_generate(report))
      report_path.to_s
    end

    private

    attr_reader :report_path, :report
  end
end
