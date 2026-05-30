class Creator < ApplicationRecord
  belongs_to :dataset

  before_validation :sync_name_fields

  validate :name_present
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :row_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  after_save :ensure_exclusive_contact, if: :contact_selected?
  after_save :sync_dataset_corresponding_contact, if: :contact_related_fields_changed?

  def contact_selected?
    is_contact? || contact?
  end

  def display_name
    return institution_name.to_s if institution_name.present?

    full_name = [ given_name, family_name ].compact.join(" ").strip
    return full_name if full_name.present?

    name.to_s
  end

  private

  def name_present
    has_legacy_name = institution_name.present? || (given_name.present? && family_name.present?)
    has_current_name = name.present?

    return if has_legacy_name || has_current_name

    errors.add(:base, "Creator must have either an institution name, both a given name and family name, or a name")
  end

  def sync_name_fields
    if name.blank?
      synthesized = ""
      if institution_name.present?
        synthesized = institution_name
      else
        synthesized = [ given_name, family_name ].compact.join(" ").strip
      end
      self.name = synthesized if synthesized.present?
    end

    if row_position.present? && position.blank?
      self.position = row_position
    elsif position.present? && row_position.blank?
      self.row_position = position
    end

    contact_value = ActiveModel::Type::Boolean.new.cast(contact)
    is_contact_value = ActiveModel::Type::Boolean.new.cast(is_contact)
    contact_selected = if will_save_change_to_contact? && will_save_change_to_is_contact?
      contact_value || is_contact_value
    elsif will_save_change_to_is_contact?
      is_contact_value
    elsif will_save_change_to_contact?
      contact_value
    else
      contact_value || is_contact_value
    end

    self.contact = contact_selected
    self.is_contact = contact_selected
  end

  def ensure_exclusive_contact
    dataset.creators.where.not(id: id).where("contact = ? OR is_contact = ?", true, true).update_all(contact: false, is_contact: false, updated_at: Time.current)
  end

  def contact_related_fields_changed?
    saved_change_to_contact? ||
      saved_change_to_is_contact? ||
      saved_change_to_name? ||
      saved_change_to_given_name? ||
      saved_change_to_family_name? ||
      saved_change_to_institution_name? ||
      saved_change_to_email?
  end

  def sync_dataset_corresponding_contact
    contact_creator = dataset.creators
      .where("contact = ? OR is_contact = ?", true, true)
      .order(Arel.sql("COALESCE(row_position, position) ASC, id ASC"))
      .first

    dataset.update_columns(
      corresponding_creator_name: contact_creator&.display_name,
      corresponding_creator_email: contact_creator&.email,
      updated_at: Time.current
    )
  end
end
