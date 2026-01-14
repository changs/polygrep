require "open3"
require "fileutils"

module Polygrep
  class Fetcher
    def initialize(config)
      @config = config
    end

    def fetch_all(&block)
      @config.repositories.each do |repo|
        fetch(repo, &block)
      end
    end

    def fetch(repo, &block)
      path = @config.repo_path(repo)

      if Dir.exist?(File.join(path, ".git"))
        update(repo, path, &block)
      else
        clone(repo, path, &block)
      end
    end

    def fetch_by_name(name, &block)
      repo = @config.repositories.find do |r|
        r[:url].include?(name)
      end

      if repo
        fetch(repo, &block)
      else
        yield(:error, name, "Repository not found in config: #{name}") if block_given?
        false
      end
    end

    private

    def clone(repo, path, &block)
      yield(:clone_start, repo[:url], path) if block_given?

      FileUtils.mkdir_p(File.dirname(path))

      cmd = ["git", "clone", "--depth", "1", "--single-branch"]
      cmd += ["--branch", repo[:branch]] if repo[:branch]
      cmd += [repo[:url], path]

      success, output = run_git(cmd)

      if success
        yield(:clone_success, repo[:url], path) if block_given?
      else
        yield(:clone_error, repo[:url], output) if block_given?
      end

      success
    end

    def update(repo, path, &block)
      yield(:update_start, repo[:url], path) if block_given?

      # Fetch latest and reset to origin
      success, output = run_git(["git", "-C", path, "fetch", "--depth", "1", "origin"])

      unless success
        yield(:update_error, repo[:url], output) if block_given?
        return false
      end

      # Determine the branch to reset to
      branch = repo[:branch] || default_branch(path)
      success, output = run_git(["git", "-C", path, "reset", "--hard", "origin/#{branch}"])

      if success
        yield(:update_success, repo[:url], path) if block_given?
      else
        yield(:update_error, repo[:url], output) if block_given?
      end

      success
    end

    def default_branch(path)
      # Try to get the default branch from remote HEAD
      success, output = run_git(["git", "-C", path, "symbolic-ref", "refs/remotes/origin/HEAD"])
      if success
        output.strip.sub("refs/remotes/origin/", "")
      else
        "main" # Fallback
      end
    end

    def run_git(cmd)
      stdout, stderr, status = Open3.capture3(*cmd)
      [status.success?, stdout + stderr]
    end
  end
end
