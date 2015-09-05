require 'mina/bundler'
require 'mina/rails'
require 'mina/git'
# require 'mina/rbenv'  # for rbenv support. (http://rbenv.org)
require 'mina/rvm'    # for rvm support. (http://rvm.io)
require 'mina/unicorn'
require "mina_sidekiq/tasks"

# Basic settings:
#   domain       - The hostname to SSH to.
#   deploy_to    - Path to deploy into.
#   repository   - Git repo to clone from. (needed by mina/git)
#   branch       - Branch name to deploy. (needed by mina/git)

# 配置主机
set :domain, '173.255.247.223'
set :deploy_to, '/var/www/rails10'
# Optional settings:
#   set :user, 'foobar'    # Username in the server to SSH to.
#   set :port, '30000'     # SSH port number.
#   set :forward_agent, true     # SSH forward_agent.
set :user, 'deployer'
set :port, '3118'
set :forward_agent, false

# 设置git
set :repository, 'git://...'
set :branch, 'master'

# For system-wide RVM install.
#   set :rvm_path, '/usr/local/rvm/bin/rvm'
set :rbenv_path, '/usr/local/rvm/bin/rvm'

# 设置sidekiq的进程保存地址
set :sidekiq_pid, "#{deploy_to}/tmp/pids/sidekiq.pid"

# 设置unicorn pid 及 进程的启动环境
set :unicorn_pid, "#{deploy_to}/tmp/pids/unicorn.pid"
set :unicorn_env, 'production'
task :environment do
  invoke :'rvm:use[ruby-2.0.0@default]'
end
# This task is the environment that is loaded for most commands, such as
# `mina deploy` or `mina rake`.
# task :environment do
  # If you're using rbenv, use this to load the rbenv environment.
  # Be sure to commit your .ruby-version or .rbenv-version to your repository.
  # invoke :'rbenv:load'

  # For those using RVM, use this to load an RVM version@gemset.
  # invoke :'rvm:use[ruby-1.9.3-p125@default]'
# end

# 设置共享文件或目录
# Manually create these paths in shared/ (eg: shared/config/database.yml) in your server.
# They will be linked in the 'deploy:link_shared_paths' step.
set :shared_paths, ['log']

# 设置目标主机目录及文件 (mina setup)
# Put any custom mkdir's in here for when `mina setup` is ran.
# For Rails apps, we'll make some of the shared paths that are shared between
# all releases.
task :setup => :environment do
  # unicorn and sidekiq needs a place to store its pid file
  queue! %[mkdir -p "#{deploy_to}/tmp/sockets/"]
  queue! %[mkdir -p "#{deploy_to}/tmp/pids/"]

  queue! %[mkdir -p "#{deploy_to}/#{shared_path}/log"]
  queue! %[mkdir -p "#{deploy_to}/#{shared_path}/config"]

  queue! %[touch "#{deploy_to}/#{shared_path}/config/database.yml"]
  queue! %[touch "#{deploy_to}/#{shared_path}/config/secrets.yml"]
  queue  %[echo "-----> Be sure to edit '#{deploy_to}/#{shared_path}/config/database.yml','secrets.yml'."]

  queue %[
    repo_host=`echo $repo | sed -e 's/.*@//g' -e 's/:.*//g'` &&
    repo_port=`echo $repo | grep -o ':[0-9]*' | sed -e 's/://g'` &&
    if [ -z "${repo_port}" ]; then repo_port=22; fi ]
end

# 增加部署命令(mina deploy)
desc "Deploys the current version to the server."
task :deploy => :environment do
  to :before_hook do
    # Put things to run locally before ssh
  end
  deploy do
    # Put things that will set up an empty directory into a fully set-up
    # instance of your project.
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'
    invoke :'deploy:cleanup'

    # to :launch do
    #   queue "mkdir -p #{deploy_to}/#{current_path}/tmp/"
    #   queue "touch #{deploy_to}/#{current_path}/tmp/restart.txt"
    # end

    # task:deploy，首先从repository的branch中clone一份代码到deploy_to目录，
    # 然后生成连接目录及文件，执行bundle, db_migrate,assets_precompile命令，
    # 最后会执行launch，里面的sidekiq 异步任务的重启，以及unicorn进程重启。
    to :launch do
      # sidekiq stop accepting new workers
      invoke :'sidekiq:quiet'
      invoke :'sidekiq:restart'
      invoke :'unicorn:restart'
    end
  end
end

# For help in making your deploy script, see the Mina documentation:
#
#  - http://nadarei.co/mina
#  - http://nadarei.co/mina/tasks
#  - http://nadarei.co/mina/settings
#  - http://nadarei.co/mina/helpers
