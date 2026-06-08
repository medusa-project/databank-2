source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record.
# On older Linux deploy hosts, force source builds to avoid glibc mismatch
# from precompiled platform gems.
if RUBY_PLATFORM.include?("linux")
  gem "pg", "~> 1.1", force_ruby_platform: true
  gem "nokogiri", force_ruby_platform: true
else
  gem "pg", "~> 1.1"
  gem "nokogiri"
end
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 8.0", ">= 8.0.2"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire: Turbo + Stimulus
gem "turbo-rails"
gem "stimulus-rails"
# Tailwind CSS via CLI
gem "tailwindcss-rails"
# HAML templates
gem "haml-rails", "~> 2.1"
# Authorization
gem "cancancan", "~> 3.6"
# OmniAuth authentication
gem "omniauth", "~> 2.1"
gem "omniauth-rails_csrf_protection", "~> 2.0"
gem "omniauth-shibboleth"
# AWS S3 for production file storage
gem "aws-sdk-s3", "~> 1.225", require: false
gem "aws-sdk-ecs", "~> 1.221", require: false
gem "aws-sdk-sqs", "~> 1.105", require: false
# Required by Active Storage variant generation
gem "image_processing", "~> 1.2"
gem "medusa_storage", git: "https://github.com/medusa-project/medusa_storage.git", ref: "2523839f6f75b9fc5500c226dd9c4212d7f54691"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# CSV parser/generator (explicit for Ruby 3.4+ compatibility)
gem "csv", "~> 3.3"
# HTTP client with digest auth support
gem "curb", "~> 1.0"
# Use Passenger standalone on deployed Rocky hosts
gem "passenger", require: false

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Use Capistrano for VM-based deployment parity with legacy databank.
  gem "capistrano-bundler", require: false
  gem "capistrano-passenger", require: false
  gem "capistrano-rails", require: false
  gem "capistrano-rbenv", require: false
  gem "airbrussh", require: false
end

gem "rspec-rails", "~> 8.0", groups: [ :development, :test ]
gem "factory_bot_rails", "~> 6.4", groups: [ :development, :test ]
gem "simplecov", "~> 0.22", require: false, group: :test
