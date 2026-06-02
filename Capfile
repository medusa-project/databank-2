# Load DSL and set up stages
require "capistrano/setup"

# Include default deployment tasks
require "capistrano/deploy"
require "capistrano/scm/git"
install_plugin Capistrano::SCM::Git

require "capistrano/rails"
require "capistrano/rbenv"
require "capistrano/bundler"
require "capistrano/rails/assets"
require "capistrano/passenger/no_hook"
require "airbrussh/capistrano"

# Load custom tasks from `lib/capistrano/tasks` if present.
Dir.glob("lib/capistrano/tasks/*.rake").each { |r| import r }
