shib_opts = YAML.load_file(File.join(Rails.root, "config", "shibboleth.yml"))[Rails.env]

Rails.application.config.middleware.use OmniAuth::Builder do
  if Rails.env.development? || Rails.env.test?
    provider :developer, fields: %i[email name role], uid_field: :email
  else
    provider :shibboleth, shib_opts.symbolize_keys
  end
end

OmniAuth.config.allowed_request_methods = %i[post get]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.on_failure = proc do |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
end

Databank2::Application.shibboleth_host = shib_opts["host"]
