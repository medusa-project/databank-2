class CuratorReportsController < ApplicationController
  before_action :require_admin_or_curator!
  before_action :set_curator_report, only: %i[show destroy download]

  def index
    @curator_reports = CuratorReport.order(created_at: :desc)
  end

  def show; end

  def request_file_audit
    CuratorReport.initiate_report_generation(
      report_type: CuratorReport::FILE_AUDIT,
      requesting_user: current_user,
      notes: params[:notes]
    )

    respond_to do |format|
      format.html { redirect_to curator_reports_path, notice: "File audit report was successfully requested." }
      format.json { head :no_content }
    end
  end

  def download
    if @curator_report.current_root.nil? || @curator_report.storage_key.blank?
      redirect_to curator_reports_path, alert: "Report file is not available."
      return
    end

    unless @curator_report.current_root.exist?(@curator_report.storage_key)
      redirect_to curator_reports_path, alert: "Report is still being generated."
      return
    end

    @curator_report.current_root.with_input_io(@curator_report.storage_key) do |io|
      send_data io.read, filename: @curator_report.storage_key, type: "text/csv", disposition: "attachment"
    end
  end

  def destroy
    @curator_report.destroy!
    redirect_to curator_reports_path, notice: "Curator report was successfully deleted."
  end

  private

  def set_curator_report
    @curator_report = CuratorReport.find(params[:id])
  end

  def require_admin_or_curator!
    return if current_user&.admin? || current_user&.curator?

    redirect_to root_path, alert: "You are not authorized to perform this action."
  end
end
