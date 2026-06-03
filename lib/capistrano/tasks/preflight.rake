namespace :deploy do
  desc "Validate demo/production host prerequisites before deploy"
  task :preflight do
    on roles(:app) do
      execute :mkdir, "-p",
              shared_path.join("config"),
              shared_path.join("log"),
              shared_path.join("tmp/pids"),
              shared_path.join("tmp/cache"),
              shared_path.join("tmp/sockets"),
              shared_path.join("tmp/uploads")

      [ "shutdown", "boot" ].each do |hook|
        hook_path = File.join(fetch(:deploy_to), "svc_hooks", hook)
        next if test("[ -x #{hook_path} ]")

        raise Capistrano::Error, "Missing executable deploy hook: #{hook_path}"
      end
    end
  end

  desc "Validate runtime configuration contract before assets precompile"
  task :config_contract do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, :exec, :rake, "config:contract"
        end
      end
    end
  end
end

namespace :bundler do
  desc "Remove cached bundle and clear stale force_ruby_platform Bundler config"
  task :clean_cache do
    on roles(:app) do
      bundle_dir = shared_path.join("bundle")
      execute :rm, "-rf", bundle_dir if test("[ -d #{bundle_dir} ]")

      within release_path do
        execute :bundle, :config, :unset, "--local", :force_ruby_platform
      end
    end
  end
end

before "deploy:check:linked_files", "deploy:preflight"
before "bundler:install", "bundler:clean_cache"
before "deploy:assets:precompile", "deploy:config_contract"
