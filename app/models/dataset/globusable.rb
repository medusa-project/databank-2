module Dataset::Globusable
  extend ActiveSupport::Concern

  # Check if dataset files are preserved/available in the preservation system
  # Requires: published status + all datafiles switched to the Medusa storage root
  # (all_medusa is set by Medusa::FinalizeIngestService, avoiding a storage check on every page load)
  def fileset_preserved?
    return @fileset_preserved if defined?(@fileset_preserved)

    @fileset_preserved = published? && all_medusa?
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
