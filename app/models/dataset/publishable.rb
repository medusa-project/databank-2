module Dataset::Publishable
  extend ActiveSupport::Concern

  EMBARGO_NONE = "none".freeze
  EMBARGO_FILE = "file".freeze
  EMBARGO_METADATA = "metadata".freeze
  EMBARGO_OPTIONS = [ EMBARGO_NONE, EMBARGO_FILE, EMBARGO_METADATA ].freeze

  HOLD_NONE = "none".freeze
  HOLD_TEMP_FILE = "files temporarily suppressed".freeze
  HOLD_TEMP_METADATA = "metadata temporarily suppressed".freeze
  HOLD_TEMP_VERSION = "version candidate under curator review".freeze
  HOLD_PERM_FILE = "files permanently suppressed".freeze
  HOLD_PERM_METADATA = "metadata permanently suppressed".freeze
  HOLD_METADATA_BLOCKING_STATES = [ HOLD_TEMP_METADATA, HOLD_PERM_METADATA, HOLD_TEMP_VERSION ].freeze
  HOLD_FILE_BLOCKING_STATES = [ HOLD_TEMP_FILE, HOLD_PERM_FILE, HOLD_TEMP_METADATA, HOLD_PERM_METADATA, HOLD_TEMP_VERSION ].freeze

  included do
    enum :publication_state, { draft: 0, published: 1 }, default: :draft

    scope :publicly_readable_now, lambda {
      published.where(is_test: false).where(
        <<~SQL.squish,
          COALESCE(NULLIF(embargo, ''), :none) <> :metadata
          AND COALESCE(NULLIF(hold_state, ''), :hold_none) NOT IN (:metadata_holds)
          OR (
            COALESCE(NULLIF(embargo, ''), :none) = :metadata
            AND release_date IS NOT NULL
            AND release_date <= :today
            AND COALESCE(NULLIF(hold_state, ''), :hold_none) NOT IN (:metadata_holds)
          )
        SQL
        none: EMBARGO_NONE,
        metadata: EMBARGO_METADATA,
        hold_none: HOLD_NONE,
        metadata_holds: HOLD_METADATA_BLOCKING_STATES,
        today: Date.current
      )
    }

    scope :files_publicly_readable_now_scope, lambda {
      published.where(is_test: false).where(
        <<~SQL.squish,
          COALESCE(NULLIF(embargo, ''), :none) NOT IN (:file, :metadata)
          AND COALESCE(NULLIF(hold_state, ''), :hold_none) NOT IN (:file_holds)
          OR (
            COALESCE(NULLIF(embargo, ''), :none) IN (:file, :metadata)
            AND release_date IS NOT NULL
            AND release_date <= :today
            AND COALESCE(NULLIF(hold_state, ''), :hold_none) NOT IN (:file_holds)
          )
        SQL
        none: EMBARGO_NONE,
        file: EMBARGO_FILE,
        metadata: EMBARGO_METADATA,
        hold_none: HOLD_NONE,
        file_holds: HOLD_FILE_BLOCKING_STATES,
        today: Date.current
      )
    }

    validates :title, presence: true, unless: :draft?
    validates :embargo, inclusion: { in: EMBARGO_OPTIONS }, allow_blank: true

    validate :release_date_required_for_embargo

    before_validation :normalize_embargo
  end

  def draft?
    publication_state == "draft"
  end

  def published?
    publication_state == "published"
  end

  def missing_publish_fields
    missing = []
    missing << "title"            if title.blank?
    missing << "description"      if description.blank?
    missing << "creators"         if creators.empty?
    missing << "contact creator"  if creators.none?(&:contact_selected?)
    missing << "email address for all creators" if creators.any? { |creator| creator.email.blank? }
    missing << "release date when embargo is file or metadata" if (file_embargoed? || metadata_embargoed?) && release_date.blank?
    missing << "relation type for each related material URI" if related_materials.any? { |material| material.uri.present? && material.relation_types.empty? }
    missing << "depositor contact" if depositor_email.blank?
    missing
  end

  def ready_to_publish?
    missing_publish_fields.empty?
  end

  def visibility
    return "Unsaved Draft" if new_record?

    case hold_state_mode
    when HOLD_TEMP_METADATA
      "Metadata and Files Temporarily Suppressed"
    when HOLD_TEMP_FILE
      "Metadata Published, Files Temporarily Suppressed"
    when HOLD_PERM_FILE
      "Metadata Published, Files Withdrawn"
    when HOLD_PERM_METADATA
      "Withdrawn"
    when HOLD_TEMP_VERSION
      "Version Candidate Under Curator Review"
    else
      return "Draft" if draft?
      return "Metadata and Files Publication Delayed (Embargoed)" if metadata_embargoed? && !embargo_released?
      return "Metadata Published, Files Publication Delayed (Embargoed)" if file_embargoed? && !embargo_released?

      "Metadata and Files Published"
    end
  end

  def curator_visibility_label
    visibility
  end

  def embargo_mode
    embargo.presence || EMBARGO_NONE
  end

  def file_embargoed?
    embargo_mode == EMBARGO_FILE
  end

  def metadata_embargoed?
    embargo_mode == EMBARGO_METADATA
  end

  def embargo_released?(on_date: Date.current)
    release_date.present? && release_date <= on_date
  end

  def hold_state_mode
    hold_state.to_s.strip.presence || HOLD_NONE
  end

  def hold_blocks_public_metadata?
    HOLD_METADATA_BLOCKING_STATES.include?(hold_state_mode)
  end

  def hold_blocks_public_files?
    HOLD_FILE_BLOCKING_STATES.include?(hold_state_mode)
  end

  def publicly_readable_now?(on_date: Date.current)
    return false if is_test?
    return false unless published?
    return false if hold_blocks_public_metadata?
    return true unless metadata_embargoed?

    embargo_released?(on_date: on_date)
  end

  def files_publicly_readable_now?(on_date: Date.current)
    return false if is_test?
    return false unless published?
    return false if hold_blocks_public_files?
    return true unless file_embargoed? || metadata_embargoed?

    embargo_released?(on_date: on_date)
  end

  private

  def normalize_embargo
    self.embargo = embargo_mode
  end

  def release_date_required_for_embargo
    return unless published?
    return unless file_embargoed? || metadata_embargoed?
    return if release_date.present?

    errors.add(:release_date, "is required when embargo is file or metadata")
  end
end
