module RamObserver
  module Collectors
    class MemoryDetail
      def collect_for(pid)
        output = `footprint #{pid} 2>/dev/null`
        parse_footprint(output)
      rescue => _e
        { compressed: 0, swap: 0 }
      end

      def enrich_entries(entries, visible_pids)
        visible_pids.each do |pid|
          entry = entries.find { |e| e.pid == pid }
          next unless entry

          detail = collect_for(pid)
          entry.compressed_bytes = detail[:compressed]
          entry.swap_bytes = detail[:swap]
        end
      end

      private

      def parse_footprint(output)
        compressed = 0
        swap = 0

        output.each_line do |line|
          if line =~ /(\d+(?:\.\d+)?)\s*(KB|MB|GB)\s+compressed/i
            compressed = parse_size($1.to_f, $2)
          end
          if line =~ /(\d+(?:\.\d+)?)\s*(KB|MB|GB)\s+swapped/i
            swap = parse_size($1.to_f, $2)
          end
        end

        { compressed: compressed, swap: swap }
      end

      def parse_size(value, unit)
        case unit.upcase
        when "KB" then (value * 1024).to_i
        when "MB" then (value * 1024 * 1024).to_i
        when "GB" then (value * 1024 * 1024 * 1024).to_i
        else value.to_i
        end
      end
    end
  end
end
