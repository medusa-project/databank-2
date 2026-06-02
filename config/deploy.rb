# config valid only for current version of Capistrano
lock "3.20.0"

set :application, "databank"
set :repo_url, "https://github.com/medusa-project/databank-2.git"

set :passenger_restart_with_touch, true
set :rbenv_type, :user
set :rbenv_ruby, "3.3.6"
set :format, :airbrussh
set :bundle_path, -> { shared_path.join("bundle") }
set :bundle_env_variables, {
  "BUNDLE_FORCE_RUBY_PLATFORM" => "true"
}

set :linked_dirs, fetch(:linked_dirs, []).push(
  "log",
  "tmp/pids",
  "tmp/cache",
  "tmp/sockets",
  "tmp/uploads"
)

set :conditionally_migrate, true
set :assets_roles, %i[web app]
set :keep_assets, 2

namespace :deploy do
  task :restart do
    on roles(:app) do
      execute "~/svc_hooks/shutdown"
      execute "~/svc_hooks/boot"
    end
  end

  after "deploy:publishing", "deploy:restart"
end
