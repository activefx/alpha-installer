require "alpha_installer/version"
require "heroku-api"
require "fog"
require "securerandom"
require "uri"

module AlphaInstaller

  class Base

    attr_accessor :app_name, :api_key, :mailchimp_api_key, :s3_id, :s3_key, :repo, :addons, :workers, :account

    DEFAULT_ADDONS = [ 'mongolab', 'logentries', 'newrelic', 'mandrill' ]
    OPTIONAL_ADDONS = [ 'openredis', 'exceptional' ]
    DEFAULT_REPO = 'git://github.com/activefx/alpha.git'

    # installer = AlphaInstaller::Base.new(app_name, { :api_key => heroku_api_key} )
    # installer.install

    def initialize(app_name, options = {})
      @app_name = app_name
      @all = options.delete(:all)
      @addons = options.delete(:addons) || []
      @workers = options.delete(:workers)
      @s3_id = options.delete(:s3_id)
      @s3_key = options.delete(:s3_key)
      @mailchimp_api_key = options.delete(:mailchimp_api_key)
      @repo = options.delete(:repo) || DEFAULT_REPO
      @account = options.delete(:account)
      @api_key = options[:api_key]
      @heroku_options = options
    end

    def all
      !!@all
    end

    def all=(value)
      @all = value
    end

    def heroku_client
      @heroku_client ||= Heroku::API.new(@heroku_options)
    end

    def install
      heroku_provisioning
      local_setup
      deploy
    end

    def heroku_provisioning
      create_app
      install_addons
      prepare_asset_sync
      output_env_file
    end

    def local_setup
      download_application
      create_rvmrc
      run_bundler
      setup_application
      create_env_file
      modify_procfile
      save_progress
      set_heroku_account
    end

    def deploy
      push_to_heroku
      provision_workers
    end

     # Create an app with a specified name
    def create_app
      post_app('name' => app_name)
    end

    def addons
      if install_all_addons?
        DEFAULT_ADDONS + OPTIONAL_ADDONS
      else
        DEFAULT_ADDONS
      end
    end

    def optional_addons
      if addons.empty?
        OPTIONAL_ADDONS
      else
        addons
      end
    end

    def install_all_addons?
      all
    end

    def install_addons
      addons.each do |addon|
        post_addon(app_name, addon)
      end
    end

    def prepare_asset_sync
      create_s3_bucket if s3_enabled?
    end

    def create_s3_bucket
      s3.directories.create(
        :key    => s3_bucket_name,
        :public => false
      )
    end

    def number_of_workers
      @workers.is_a?(Integer) ? @workers : 1
    end

    def output_env_file
      print env_file
    end

    def download_application
      `git clone -o alpha #{repo} #{app_name}`
    end

    def create_rvmrc
      `rvm use 1.9.3-p392@#{app_name} --create`
    end

    def run_bundler
      `bundle install`
    end

    def setup_application
      `rake development:install`
    end

    def create_env_file
      File.open(".env", 'w') { |f| f.puts env_file }
    end

    def modify_procfile
      return unless app_includes_workers?
      File.open(".env", 'w') { |f| f.puts procfile }
    end

    def procfile
      [ "web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb" ].tap do |cmds|
        if app_includes_workers?
          cmds << "worker: bundle exec sidekiq -C ./config/sidekiq.yml"
        else
          cmds << "# worker: bundle exec sidekiq -C ./config/sidekiq.yml"
        end
      end.join("\n")
    end

    def save_progress
      `git commit -a -m 'installed alpha'`
    end

    def add_git_remote
      `git remote add heroku #{heroku_git_repo}`
    end

    def set_heroku_account
      if account
        `heroku accounts:set #{account}`
      end
    end

    def push_to_heroku
      `git push heroku master`
    end

    def provision_workers
      return unless app_includes_workers? && number_of_workers > 1
      post_ps_scale(app_name, 'worker', number_of_workers)
    end

    def sidekiq_enabled?
      app_includes_workers? && addons.include?('openredis')
    end

    def app_includes_workers?
      !!(all || workers)
    end

    def new_secret_token
      SecureRandom.hex(64)
    end

    def config_vars
      get_config_vars(app_name).body
    end

    def config_var(var_name)
      config_vars[var_name]
    end

    def heroku_git_repo
      get_app('alpha1app').data[:body]['git_url']
    end

    def method_missing(meth, *args, &block)
      heroku_client.send(meth, *args, &block)
    end

    protected

    def extra_mongolab_config_vars
      uri = mongolab_uri
      [
        "MONGODB_USERNAME=#{uri.user}",        # username
        "MONGODB_PASSWORD=#{uri.password}",    # password
        "MONGODB_HOST=#{uri.host}",            # host
        "MONGODB_PORT=#{uri.port}",            # port
        "MONGODB_PROTOCOL=#{uri.scheme}",      # mongodb
        "MONGODB_DATABASE=#{uri.path[1..-1]}"  # db name
      ]
    end

    def mongolab_uri
      URI.parse config_var("MONGOLAB_URI")
    end

    def env_file
      extra_mongolab_config_vars.tap do |vars|
        config_vars.each do |key, value|
          vars << "#{key}=#{value}"
        end
        if sidekiq_enabled?
          vars << "OPENREDIS_DEV_URL=#{openredis_dev_url}"
          vars << "QUEUE=*"
        end
        if mailchimp_enabled?
          vars << "MAILCHIMP_API_KEY=#{mailchimp_api_key}"
        end
        if s3_enabled?
          vars << "AWS_ACCESS_KEY_ID=#{s3_id}"
          vars << "AWS_SECRET_ACCESS_KEY=#{s3_key}"
          vars << "FOG_DIRECTORY=#{s3_bucket_name}"
        end
        vars << "SECRET_TOKEN=#{new_secret_token}"
        vars << "HEROKU_APP_NAME=#{app_name}"
        vars << "HEROKU_API_KEY=#{api_key}"
      end.join("\n")
    end

    def s3
      Fog::Storage.new({
        :provider                 => 'AWS',
        :aws_access_key_id        => s3_id,
        :aws_secret_access_key    => s3_key
      })
    end

    def s3_enabled?
      !!(s3_id && s3_key)
    end

    def s3_bucket_name
      "#{app_name}-assets"
    end

    def mailchimp_enabled?
      mailchimp_api_key
    end

    def openredis_dev_url
      config_var("OPENREDIS_URL").gsub(/(?<=@).+/, "proxy.openredis.com:10868")
    end

  end

end

