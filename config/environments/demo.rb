require_relative "production"

Rails.application.configure do
  # Keep demo behavior aligned with production for deploy validation.
  config.credentials.content_path = Rails.root.join("config/credentials/demo.yml.enc")
  config.credentials.key_path = Rails.root.join("config/credentials/demo.key")
end
