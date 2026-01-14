module Polygrep
  class Searcher
    def initialize(config)
      @config = config
    end

    def search(pattern, options = {})
      unless ripgrep_available?
        raise SearchError, "ripgrep (rg) is not installed. Install it with: brew install ripgrep"
      end

      cmd = build_command(pattern, options)

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
  end

  class SearchError < StandardError; end
end
