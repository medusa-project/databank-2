module Dataset::Globusable
  extend ActiveSupport::Concern

  # Check if dataset files are preserved/available in the preservation system
  # Files must be ingested successfully to be downloadable
  def fileset_preserved?
    return @fileset_preserved if defined?(@fileset_preserved)

    @fileset_preserved = external_delivery_attempts.exists?(
      integration: :ingest,
      status: :succeeded
    )
  end

  # Check if dataset files are available via Globus download
  # Requires: published status + all datafiles copied to the Globus download root
  # (all_globus is set by Globus::PublicCopyService and cleared by Globus::SuppressionService)
  def globus_downloadable?
    return @globus_downloadable if defined?(@globus_downloadable)

    @globus_downloadable = published? && all_globus?
  end

  # Check if dataset has external files (files not in the repository system)
  def external_files?
    external_files_note.to_s.strip.present? || external_files_link.to_s.strip.present?
  end
end
