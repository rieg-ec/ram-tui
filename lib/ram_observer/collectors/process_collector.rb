module RamObserver
  module Collectors
    class ProcessCollector
      def collect
        output = `ps -axo pid,ppid,rss,vsz,etime,lstart,command 2>/dev/null`
        parse(output)
      end

      def parse(output)
        lines = output.strip.split("\n")
        lines.shift # skip header
        lines.filter_map { |line| parse_line(line) }
      end

      private

      def parse_line(line)
        # PID  PPID   RSS      VSZ ELAPSED STARTED                      COMMAND
        # Fields: pid, ppid, rss, vsz are numeric. etime is token.
        # lstart is like "Wed Jan 28 17:21:44 2026" (5 tokens). command is rest.
        tokens = line.strip.split(/\s+/)
        return nil if tokens.length < 11

        pid = tokens[0].to_i
        ppid = tokens[1].to_i
        rss = tokens[2].to_i
        vsz = tokens[3].to_i
        etime = tokens[4]
        # lstart is 5 tokens: day month date time year
        started = tokens[5..9].join(" ")
        command = tokens[10..].join(" ")

        ProcessEntry.new(
          pid: pid, ppid: ppid, rss_kb: rss, vsz_kb: vsz,
          command: command, elapsed: etime, started: started
        )
      rescue => _e
        nil
      end
    end
  end
end
