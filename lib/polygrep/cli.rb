require "thor"

module Polygrep
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "fetch [REPOS...]", "Fetch or update repositories"
    long_desc <<-DESC
      Fetches the latest code from configured repositories using shallow clones.
      If REPOS are specified, only those matching repositories are fetched.
      Otherwise, all configured repositories are fetched.
    DESC
    option :config, aliases: "-c", desc: "Path to config file"
    def fetch(*repos)
      config = load_config(options[:config])
      fetcher = Fetcher.new(config)

      callback = method(:fetch_callback)

      if repos.empty?
        fetcher.fetch_all(&callback)
      else
        repos.each { |name| fetcher.fetch_by_name(name, &callback) }
      end
    end

    desc "search PATTERN", "Search across all repositories"
    long_desc <<-DESC
      Searches for PATTERN across all fetched repositories using ripgrep.
      Supports regex patterns and common ripgrep options.
    DESC
    option :config, aliases: "-c", desc: "Path to config file"
    option :ignore_case, aliases: "-i", type: :boolean, desc: "Case insensitive search"
    option :type, aliases: "-t", desc: "File type filter (e.g., ruby, js, py)"
    option :context, aliases: "-C", type: :numeric, desc: "Lines of context"
    option :after, aliases: "-A", type: :numeric, desc: "Lines after match"
    option :before, aliases: "-B", type: :numeric, desc: "Lines before match"
    option :glob, aliases: "-g", desc: "Glob pattern filter"
    option :skip_noise, aliases: "-N", type: :boolean, desc: "Exclude tests, specs, fixtures, lock files, and long lines (base64)"
    def search(pattern)
      config = load_config(options[:config])
      searcher = Searcher.new(config)

      search_options = {
        ignore_case: options[:ignore_case],
        type: options[:type],
        context: options[:context],
        after: options[:after],
        before: options[:before],
        glob: options[:glob],
        skip_noise: options[:skip_noise]
      }.compact

      searcher.search(pattern, search_options)
    rescue SearchError => e
      say_error(e.message)
      exit 1
    end

    desc "list", "List configured repositories and their status"
    option :config, aliases: "-c", desc: "Path to config file"
    def list
      config = load_config(options[:config])

      say "Storage path: #{config.storage_path}\n\n"
      say "Repositories:"

      config.repositories.each do |repo|
        path = config.repo_path(repo)
        status = if Dir.exist?(File.join(path, ".git"))
                   "\e[32mcloned\e[0m"
                 else
                   "\e[33mnot cloned\e[0m"
                 end

        branch_info = repo[:branch] ? " (branch: #{repo[:branch]})" : ""
        say "  #{repo[:url]}#{branch_info} - #{status}"
      end
    end

    desc "init", "Create a sample configuration file"
    option :path, aliases: "-p", desc: "Path for config file", default: Config::DEFAULT_CONFIG_PATH
    def init
      path = File.expand_path(options[:path])

      if File.exist?(path)
        say_error "Config file already exists: #{path}"
        exit 1
      end

      FileUtils.mkdir_p(File.dirname(path))

      sample_config = <<~YAML
        # Polygrep configuration
        # Storage path for cloned repositories (default: ~/.polygrep/repos)
        storage_path: ~/.polygrep/repos

        # List of repositories to clone
        repositories:
          # Simple format - just the URL
          - url: https://github.com/rails/rails

          # Extended format - with branch
          # - url: https://gitlab.com/org/repo
          #   branch: develop
      YAML

      File.write(path, sample_config)
      say "Created config file: #{path}"
      say "Edit this file to add your repositories, then run 'polygrep fetch'"
    end

    desc "version", "Show version"
    def version
      say "polygrep #{VERSION}"
    end

    private

    def load_config(path)
      Config.new(path)
    rescue ConfigError => e
      say_error(e.message)
      exit 1
    end

    def fetch_callback(event, url_or_name, detail)
      case event
      when :clone_start
        say "Cloning #{url_or_name}..."
      when :clone_success
        say "  \e[32mCloned to #{detail}\e[0m"
      when :clone_error
        say_error "  Failed to clone: #{detail}"
      when :update_start
        say "Updating #{url_or_name}..."
      when :update_success
        say "  \e[32mUpdated\e[0m"
      when :update_error
        say_error "  Failed to update: #{detail}"
      when :error
        say_error detail
      end
    end

    def say_error(message)
      $stderr.puts "\e[31m#{message}\e[0m"
    end
  end
end
