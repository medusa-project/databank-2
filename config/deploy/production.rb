server "databank-prod-rocky.library.illinois.edu", user: "databank", roles: %w[app db web]

set :rails_env, "production"
set :ssh_options, {
  forward_agent: true,
  auth_methods: [ "publickey" ],
  keys: [ "#{Dir.home}/.ssh/medusa-2023.pem" ]
}

ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }.call

set :deploy_to, "/home/databank"
set :linked_files, fetch(:linked_files, []).push("config/credentials/production.key", "nginx.conf.erb")
