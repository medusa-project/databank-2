class AppSetting < ApplicationRecord
  SYSTEM_MESSAGE_KEY = "system_message".freeze

  validates :key, presence: true, uniqueness: true

  def self.system_message
    find_by(key: SYSTEM_MESSAGE_KEY)&.value.to_s
  end

  def self.system_message=(message)
    cleaned_message = message.to_s.strip
    setting = find_or_initialize_by(key: SYSTEM_MESSAGE_KEY)

    if cleaned_message.blank?
      setting.destroy! if setting.persisted?
    else
      setting.value = cleaned_message
      setting.save!
    end
  end
end
