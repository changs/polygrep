require "yaml"
require "fileutils"

module Polygrep
  class Config
    DEFAULT_CONFIG_PATH = File.expand_path("~/.polygrep/repos.yml")
    DEFAULT_STORAGE_PATH = File.expand_path("~/.polygrep/repos")

    attr_reader :storage_path, :repositories

    def initialize(config_path = nil)
      @config_path = config_path || DEFAULT_CONFIG_PATH
      load_config
    end

    def self.config_exists?(path = nil)
      File.exist?(path || DEFAULT_CONFIG_PATH)
    end

    def repo_path(repo)
      File.join(storage_path, repo_dirname(repo))
    end

    def repo_dirname(repo)
      # Extract org/repo from URL and use as directory name
      # e.g., https://github.com/rails/rails -> github.com_rails_rails
      uri = repo[:url]
      uri.sub(%r{^https?://}, "").gsub("/", "_")
    end

    private

    def load_config
      unless File.exist?(@config_path)
        raise ConfigError, "Config file not found: #{@config_path}\nRun 'polygrep init' to create one."
      end

      data = YAML.load_file(@config_path, symbolize_names: true)

      @storage_path = File.expand_path(data[:storage_path] || DEFAULT_STORAGE_PATH)
      @repositories = parse_repositories(data[:repositories] || [])

      FileUtils.mkdir_p(@storage_path)
    end

    def parse_repositories(repos)
      repos.map do |repo|
        if repo.is_a?(String)
          { url: repo, branch: nil }
        else
          { url: repo[:url], branch: repo[:branch] }
        end
      end
    end
  end

  class ConfigError < StandardError; end
end
