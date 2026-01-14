module Polygrep
  class Searcher
    # Directories commonly containing test files
    NOISE_DIR_PATTERNS = %w[
      !**/spec/**
      !**/specs/**
      !**/test/**
      !**/tests/**
      !**/__tests__/**
      !**/fixtures/**
      !**/cassettes/**
    ].freeze

    # File patterns to exclude
    NOISE_FILE_PATTERNS = %w[
      !*.spec.*
      !*.test.*
      !*_spec.rb
      !*_test.rb
      !*_test.go
      !*.min.js
      !*.min.css
      !package-lock.json
      !yarn.lock
      !Gemfile.lock
    ].freeze

    def initialize(config)
      @config = config
    end

    def search(pattern, options = {})
      unless ripgrep_available?
        raise SearchError, "ripgrep (rg) is not installed. Install it with: brew install ripgrep"
      end

      cmd = build_command(pattern, options)

      if options[:debug]
        $stderr.puts "\e[33m$ #{cmd.join(' ')}\e[0m"
      end

      # Stream output directly to stdout for real-time results
      system(*cmd)
    end

    def ripgrep_available?
      system("which rg > /dev/null 2>&1")
    end

    private

    def build_command(pattern, options)
      cmd = ["rg"]

      # Add common options
      cmd << "-i" if options[:ignore_case]
      cmd += ["-t", options[:type]] if options[:type]
      cmd += ["-C", options[:context].to_s] if options[:context]
      cmd += ["-A", options[:after].to_s] if options[:after]
      cmd += ["-B", options[:before].to_s] if options[:before]
      cmd += ["-g", options[:glob]] if options[:glob]

      # Exclude noise (tests, base64 content, etc.)
      if options[:skip_noise]
        add_noise_exclusions(cmd)
      end

      # Line numbers on by default
      cmd << "-n" unless options[:no_line_numbers]

      # Color output
      cmd << "--color=always" if $stdout.tty?

      # Add pattern
      cmd << pattern

      # Search in storage path
      cmd << @config.storage_path

      cmd
    end

    def add_noise_exclusions(cmd)
      # Must include a positive glob first, otherwise exclusions filter everything
      # Also explicitly exclude hidden files since glob overrides default behavior
      cmd.push("-g", "*", "--no-hidden")

      # Exclude test directories and files
      (NOISE_DIR_PATTERNS + NOISE_FILE_PATTERNS).each do |pattern|
        cmd.push("-g", pattern)
      end

      # Exclude lines with base64 encoded content (data URIs, long base64 strings)
      cmd.push("--max-columns", "500")  # Skip very long lines (likely base64/minified)
      cmd.push("--max-columns-preview")  # Show truncated preview instead of skipping
    end
  end

  class SearchError < StandardError; end
end
