class MigrationRun < ApplicationRecord
  RUN_TYPES = %w[
    users_bundle_import
    bundle_import
    guides_bundle_import
    featured_researchers_bundle_import
    permissions_bundle_import
    dataset_access_grants_bundle_import
    medusa_ingests_bundle_import
    download_metrics_bundle_import
    audits_bundle_import
    sample_fetch
    sample_import
  ].freeze
  STATUSES = %w[started completed failed].freeze

  validates :run_type, presence: true, inclusion: { in: RUN_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true
end
