namespace :config do
  def contract_source(credentials_value:, env_key:, default_used: false)
    return "credentials" unless credentials_value.blank?
    return "env:#{env_key}" if ENV.key?(env_key)
    return "default" if default_used

    "missing"
  end

  desc "Validate required runtime configuration for the current Rails environment"
  task contract: :environment do
    errors = []
    warnings = []

    require_value = lambda do |label, value|
      return unless value.respond_to?(:blank?) ? value.blank? : value.nil?

      errors << "#{label} is missing"
    end

    bool = lambda do |value|
      ActiveModel::Type::Boolean.new.cast(value)
    end

    # Core app metadata required in all deployed environments.
    require_value.call("IDB_CONFIG.app.url", IDB_CONFIG.dig("app", "url"))
    require_value.call("IDB_CONFIG.app.root_url_text", IDB_CONFIG.dig("app", "root_url_text"))
    require_value.call("IDB_CONFIG.mail.from", IDB_CONFIG.dig("mail", "from"))

    storage_roots = STORAGE_CONFIG.fetch(:storage, [])
    required_root_names = %w[draft medusa globus_download globus_ingest message reports tmpfs]
    roots_by_name = storage_roots.index_by { |root| root.fetch(:name, "").to_s }

    missing_roots = required_root_names - roots_by_name.keys
    if missing_roots.any?
      errors << "STORAGE_CONFIG.storage is missing roots: #{missing_roots.join(", ")}"
    end

    roots_by_name.each do |name, root|
      type = root.fetch(:type, "").to_s

      case type
      when "s3"
        require_value.call("STORAGE_CONFIG.storage[#{name}].region", root[:region])
        require_value.call("STORAGE_CONFIG.storage[#{name}].bucket", root[:bucket])
      when "filesystem"
        require_value.call("STORAGE_CONFIG.storage[#{name}].path", root[:path])
      else
        errors << "STORAGE_CONFIG.storage[#{name}].type must be 's3' or 'filesystem' (found '#{type}')"
      end
    end

    if bool.call(IDB_CONFIG.dig("doi", "strict"))
      require_value.call("IDB_CONFIG.doi.api_base_url", IDB_CONFIG.dig("doi", "api_base_url"))
      require_value.call("IDB_CONFIG.doi.username", IDB_CONFIG.dig("doi", "username"))
      require_value.call("IDB_CONFIG.doi.password", IDB_CONFIG.dig("doi", "password"))
    end

    if bool.call(IDB_CONFIG.dig("ingest", "events_enabled"))
      require_value.call("IDB_CONFIG.ingest.rabbitmq_url", IDB_CONFIG.dig("ingest", "rabbitmq_url"))
      require_value.call("IDB_CONFIG.ingest.events_exchange", IDB_CONFIG.dig("ingest", "events_exchange"))
      require_value.call("IDB_CONFIG.ingest.events_routing_key", IDB_CONFIG.dig("ingest", "events_routing_key"))
    end

    if bool.call(IDB_CONFIG.dig("globus", "transfer_enabled"))
      require_value.call("IDB_CONFIG.globus.transfer_endpoint", IDB_CONFIG.dig("globus", "transfer_endpoint"))
      require_value.call("IDB_CONFIG.globus.transfer_token", IDB_CONFIG.dig("globus", "transfer_token"))
      require_value.call("IDB_CONFIG.globus.source_collection", IDB_CONFIG.dig("globus", "source_collection"))
      require_value.call("IDB_CONFIG.globus.destination_collection", IDB_CONFIG.dig("globus", "destination_collection"))
    end

    active_storage_service = Rails.application.config.active_storage.service.to_s
    if active_storage_service == "amazon"
      raw_storage = ERB.new(File.read(Rails.root.join("config", "storage.yml"))).result
      parsed_storage = YAML.safe_load(raw_storage, aliases: true) || {}
      amazon_storage = parsed_storage.fetch("amazon", {})

      require_value.call("config/storage.yml amazon.region", amazon_storage["region"])
      require_value.call("config/storage.yml amazon.bucket", amazon_storage["bucket"])

      if amazon_storage["access_key_id"].blank? || amazon_storage["secret_access_key"].blank?
        warnings << "Active Storage amazon credentials are blank; this is valid only with instance/profile-based IAM auth"
      end
    end

    if errors.any?
      message = +"Configuration contract check failed for RAILS_ENV=#{Rails.env}.\n"
      message << errors.map { |error| "- #{error}" }.join("\n")
      abort(message)
    end

    puts "Configuration contract check passed for RAILS_ENV=#{Rails.env}."
    warnings.each { |warning| puts "WARN: #{warning}" }
  end

  desc "Print non-secret config source report for current Rails environment"
  task contract_report: :environment do
    puts "Config source report for RAILS_ENV=#{Rails.env}"

    rows = []

    rows << [
      "idb.app.url",
      contract_source(
        credentials_value: Rails.application.credentials.dig(:app_url),
        env_key: "APP_URL",
        default_used: true
      ),
      IDB_CONFIG.dig("app", "url").presence ? "set" : "missing"
    ]

    rows << [
      "idb.app.root_url_text",
      contract_source(
        credentials_value: Rails.application.credentials.dig(:root_url_text),
        env_key: "ROOT_URL_TEXT",
        default_used: true
      ),
      IDB_CONFIG.dig("app", "root_url_text").presence ? "set" : "missing"
    ]

    rows << [
      "idb.mail.from",
      contract_source(
        credentials_value: Rails.application.credentials.dig(:system_user_email),
        env_key: "IDB_MAIL_FROM",
        default_used: true
      ),
      IDB_CONFIG.dig("mail", "from").presence ? "set" : "missing"
    ]

    rows << [
      "storage.region",
      contract_source(
        credentials_value: Rails.application.credentials.dig(:aws, :region),
        env_key: "STORAGE_S3_REGION",
        default_used: true
      ),
      STORAGE_CONFIG.dig(:storage, 0, :region).presence ? "set" : "missing"
    ]

    {
      "draft_bucket" => "STORAGE_DRAFT_BUCKET",
      "medusa_bucket" => "STORAGE_MEDUSA_BUCKET",
      "globus_bucket" => "STORAGE_GLOBUS_BUCKET",
      "draft_prefix" => "STORAGE_DRAFT_PREFIX",
      "medusa_prefix" => "STORAGE_MEDUSA_PREFIX",
      "globus_download_prefix" => "STORAGE_GLOBUS_DOWNLOAD_PREFIX"
    }.each do |credentials_key, env_key|
      value = Rails.application.credentials.dig(:storage, credentials_key.to_sym)
      source = contract_source(
        credentials_value: value,
        env_key: env_key,
        default_used: credentials_key.end_with?("prefix")
      )
      status = value.present? || ENV.key?(env_key) || credentials_key.end_with?("prefix") ? "set" : "missing"
      rows << [ "storage.#{credentials_key}", source, status ]
    end

    active_storage_bucket_source = if Rails.application.credentials.dig(:storage, :active_storage_bucket).present?
      "credentials"
    elsif Rails.application.credentials.dig(:storage, :draft_bucket).present?
      "credentials:fallback(draft_bucket)"
    elsif ENV.key?("AWS_S3_BUCKET")
      "env:AWS_S3_BUCKET"
    else
      "missing"
    end
    rows << [ "active_storage.bucket", active_storage_bucket_source, active_storage_bucket_source == "missing" ? "missing" : "set" ]

    rows.each do |row|
      puts "- #{row[0]} | source=#{row[1]} | status=#{row[2]}"
    end
  end
end
