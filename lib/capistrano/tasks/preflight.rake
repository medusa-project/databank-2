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
end

before "deploy:check:linked_files", "deploy:preflight"
