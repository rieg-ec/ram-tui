module RamObserver
  class ProcessEntry
    attr_accessor :pid, :ppid, :rss_kb, :vsz_kb, :command, :comm_name,
                  :elapsed, :started, :dirty_bytes, :swap_bytes,
                  :children, :expanded, :depth, :parent

    def initialize(pid:, ppid:, rss_kb:, vsz_kb:, command:, elapsed:, started:)
      @pid = pid
      @ppid = ppid
      @rss_kb = rss_kb
      @vsz_kb = vsz_kb
      @command = command
      @comm_name = extract_comm_name(command)
      @elapsed = elapsed
      @started = started
      @dirty_bytes = 0
      @swap_bytes = 0
      @children = []
      @expanded = false
      @depth = 0
      @parent = nil
    end

    def rss_bytes
      @rss_kb * 1024
    end

    def vsz_bytes
      @vsz_kb * 1024
    end

    def leaf?
      @children.empty?
    end

    def total_rss_kb
      @rss_kb + @children.sum { |c| c.total_rss_kb }
    end

    def age_seconds
      parse_elapsed(@elapsed)
    end

    def age_human
      secs = age_seconds
      return "#{secs}s" if secs < 60
      mins = secs / 60
      return "#{mins}m" if mins < 60
      hours = mins / 60
      return "#{hours}h #{mins % 60}m" if hours < 24
      days = hours / 24
      "#{days}d #{hours % 24}h"
    end

    private

    def extract_comm_name(cmd)
      cmd = cmd.to_s.strip
      return "[unknown]" if cmd.empty?

      # Detect Chromium/Electron helper processes (Chrome, Slack, Spotify, etc.)
      if cmd.include?("--type=")
        return chromium_helper_name(cmd)
      end

      basename = File.basename(cmd.split(/\s+/).first.to_s)
      basename.empty? ? cmd : basename
    end

    def chromium_helper_name(cmd)
      # Extract app name from .app path
      app_name = if cmd =~ %r{/([^/]+)\.app/}
                   $1.sub(/\s+Helper.*/, "")
                 else
                   "Chromium"
                 end

      # Extract --type=
      type = cmd[/--type=(\S+)/, 1] || "unknown"

      # Refine the label
      label = case type
              when "renderer"
                cmd.include?("--extension-process") ? "extension" : "renderer"
              when "gpu-process"
                "gpu"
              when "utility"
                sub = cmd[/--utility-sub-type=(\S+)/, 1] || ""
                short = sub.split(".").find { |p| !%w[mojom].include?(p) && p =~ /[A-Z]/ }
                short ? short.gsub(/Service$/, "").downcase : "utility"
              else
                type
              end

      "#{app_name}: #{label}"
    end

    def parse_elapsed(str)
      # etime format: [[dd-]hh:]mm:ss
      parts = str.strip.split(/[-:]/)
      case parts.length
      when 2 then parts[0].to_i * 60 + parts[1].to_i
      when 3 then parts[0].to_i * 3600 + parts[1].to_i * 60 + parts[2].to_i
      when 4 then parts[0].to_i * 86400 + parts[1].to_i * 3600 + parts[2].to_i * 60 + parts[3].to_i
      else 0
      end
    end
  end
end
