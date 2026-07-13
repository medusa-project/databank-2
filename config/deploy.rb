# config valid only for current version of Capistrano
lock "3.20.1"

set :application, "databank"
set :repo_url, "https://github.com/medusa-project/databank-2.git"

set :passenger_restart_with_touch, true
set :rbenv_type, :user
set :rbenv_ruby, "3.3.6"
set :format, :airbrussh
set :bundle_path, -> { shared_path.join("bundle") }

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
  task :ensure_fresh_metrics do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, :exec, :rake, "metrics:ensure_fresh_metrics"
        end
      end
    end
  end

  task :restart do
    on roles(:app) do
      execute "~/svc_hooks/shutdown"
      execute "~/svc_hooks/boot"
    end
  end

  after "deploy:publishing", "deploy:ensure_fresh_metrics"
  after "deploy:ensure_fresh_metrics", "deploy:restart"
end
