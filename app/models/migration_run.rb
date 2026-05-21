class MigrationRun < ApplicationRecord
  RUN_TYPES = %w[bundle_import sample_fetch sample_import].freeze
  STATUSES = %w[started completed failed].freeze

  validates :run_type, presence: true, inclusion: { in: RUN_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true
end
