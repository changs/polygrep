require "bubbletea"

module Polygrep
  class Browser
    include Bubbletea::Model

    PREVIEW_CONTEXT = 5  # Lines of context around match

    attr_reader :selected_result

    def initialize(results)
      @results = parse_results(results)
      @selected = 0
      @preview_scroll = 0
      @width = 120
      @height = 30
      @selected_result = nil  # Set when user presses Enter
    end

    def init
      [self, nil]
    end

    def update(message)
      case message
      when Bubbletea::WindowSizeMessage
        @width = message.width
        @height = message.height
        [self, nil]
      when Bubbletea::KeyMessage
        handle_key(message)
      else
        [self, nil]
      end
    end

    def view
      return "No results found." if @results.empty?

      list_view = render_list
      preview_view = render_preview

      # Layout: list on left, preview on right
      list_width = [@width / 3, 50].max
      preview_width = @width - list_width - 3

      lines = []
      list_lines = list_view.split("\n")
      preview_lines = preview_view.split("\n")

      max_lines = @height - 2
      max_lines.times do |i|
        left = truncate_ansi(list_lines[i] || "", list_width)
        right = truncate_ansi(preview_lines[i] || "", preview_width)
        lines << "#{left} \e[0m\u2502 #{right}\e[0m"
      end

      header = " #{@results.length} results | j/k:navigate | Enter:open | q:quit "
      styled_header = style(header, fg: 240, bg: 236)

      "#{styled_header}\n#{lines.join("\n")}"
    end

    private

    # Simple ANSI styling helper
    def style(text, fg: nil, bg: nil, bold: false)
      codes = []
      codes << "1" if bold
      codes << "38;5;#{fg}" if fg
      codes << "48;5;#{bg}" if bg
      return text if codes.empty?
      "\e[#{codes.join(';')}m#{text}\e[0m"
    end

    # Truncate/pad text with ANSI codes to exact visible width
    def truncate_ansi(text, width)
      # Strip ANSI codes to count visible length
      visible = text.gsub(/\e\[[0-9;]*m/, "")
      visible_len = visible.length

      if visible_len <= width
        # Pad with spaces, preserving any trailing reset
        text + " " * (width - visible_len)
      else
        # Truncate by visible characters, preserving ANSI codes
        result = ""
        visible_count = 0
        i = 0
        while i < text.length && visible_count < width
          if text[i] == "\e"
            # Capture entire ANSI sequence
            seq_end = text.index("m", i)
            if seq_end
              result += text[i..seq_end]
              i = seq_end + 1
            else
              i += 1
            end
          else
            result += text[i]
            visible_count += 1
            i += 1
          end
        end
        result
      end
    end

    def handle_key(message)
      case message.to_s
      when "q", "ctrl+c", "esc"
        [self, Bubbletea.quit]
      when "j", "down"
        @selected = [@selected + 1, @results.length - 1].min
        @preview_scroll = 0
        [self, nil]
      when "k", "up"
        @selected = [@selected - 1, 0].max
        @preview_scroll = 0
        [self, nil]
      when "ctrl+d"
        @selected = [@selected + 10, @results.length - 1].min
        @preview_scroll = 0
        [self, nil]
      when "ctrl+u"
        @selected = [@selected - 10, 0].max
        @preview_scroll = 0
        [self, nil]
      when "g"
        @selected = 0
        @preview_scroll = 0
        [self, nil]
      when "G"
        @selected = @results.length - 1
        @preview_scroll = 0
        [self, nil]
      when "enter"
        @selected_result = @results[@selected]
        [self, Bubbletea.quit]
      else
        [self, nil]
      end
    end

    def render_list
      visible_height = @height - 3
      start_idx = [0, @selected - visible_height + 3].max

      lines = []
      @results[start_idx, visible_height].each_with_index do |result, idx|
        actual_idx = start_idx + idx
        prefix = actual_idx == @selected ? "\u25b6 " : "  "

        # Shorten the path for display
        short_path = result[:file].sub(%r{.*/repos/[^/]+/}, "")
        display = "#{short_path}:#{result[:line_num]}"

        if actual_idx == @selected
          lines << style("#{prefix}#{display}", fg: 212, bold: true)
        else
          lines << "#{prefix}#{display}"
        end
      end

      lines.join("\n")
    end

    def render_preview
      return "Select a result to preview" if @results.empty?

      result = @results[@selected]
      return "File not found" unless File.exist?(result[:file])

      lines = File.readlines(result[:file]) rescue []
      return "Could not read file" if lines.empty?

      line_num = result[:line_num]
      start_line = [line_num - PREVIEW_CONTEXT - 1, 0].max
      end_line = [line_num + PREVIEW_CONTEXT - 1, lines.length - 1].min

      preview_lines = []

      # Header
      short_file = result[:file].sub(%r{.*/repos/}, "")
      preview_lines << style(" #{short_file} ", fg: 255, bg: 62)
      preview_lines << ""

      (start_line..end_line).each do |i|
        line_content = lines[i]&.chomp || ""
        line_display = "#{(i + 1).to_s.rjust(4)} \u2502 #{line_content}"

        if i + 1 == line_num
          # Highlight the matched line
          preview_lines << style(line_display, fg: 226, bold: true)
        else
          preview_lines << style(line_display, fg: 250)
        end
      end

      preview_lines.join("\n")
    end

    def parse_results(output)
      output.lines.filter_map do |line|
        # Format: /path/to/file:123:matched content
        if line =~ /\A(.+?):(\d+):(.*)$/
          { file: $1, line_num: $2.to_i, content: $3 }
        end
      end
    end
  end
end
