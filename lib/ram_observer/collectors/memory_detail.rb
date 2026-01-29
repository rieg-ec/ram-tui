module RamObserver
  module Collectors
    class MemoryDetail
      def collect_for(pid)
        output = `vmmap -summary #{pid.to_i} 2>/dev/null`
        parse_vmmap(output)
      rescue => _e
        { dirty: 0, swap: 0 }
      end

      private

      # Parse the first TOTAL line from vmmap -summary output.
      # Columns: VIRTUAL, RESIDENT, DIRTY, SWAPPED, VOLATILE, NONVOL, EMPTY, COUNT
      def parse_vmmap(output)
        dirty = 0
        swap = 0

        output.each_line do |line|
          next unless line.start_with?("TOTAL")
          tokens = line.split(/\s+/)
          # TOTAL <virtual> <resident> <dirty> <swapped> ...
          dirty = parse_size_token(tokens[3]) if tokens[3]
          swap = parse_size_token(tokens[4]) if tokens[4]
          break # only first TOTAL line
        end

        { dirty: dirty, swap: swap }
      end

      def parse_size_token(token)
        return 0 unless token
        if token =~ /^([\d.]+)(KB|MB|GB|TB)$/i
          value = $1.to_f
          case $2.upcase
          when "KB" then (value * 1024).to_i
          when "MB" then (value * 1024 * 1024).to_i
          when "GB" then (value * 1024 * 1024 * 1024).to_i
          when "TB" then (value * 1024 * 1024 * 1024 * 1024).to_i
          else 0
          end
        elsif token =~ /^\d+$/
          token.to_i
        else
          0
        end
      end
    end
  end
end
