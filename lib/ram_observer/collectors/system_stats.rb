module RamObserver
  module Collectors
    class SystemStats
      Stats = Struct.new(
        :total_bytes, :used_bytes, :free_bytes,
        :active_bytes, :inactive_bytes, :wired_bytes, :compressed_bytes,
        :swap_total_bytes, :swap_used_bytes,
        :pressure_level, :pressure_percent,
        keyword_init: true
      )

      def collect
        page_size, pages = parse_vm_stat
        total = parse_total_memory
        swap_total, swap_used = parse_swap
        pressure_level, pressure_pct = parse_pressure

        active = (pages[:active] || 0) * page_size
        inactive = (pages[:inactive] || 0) * page_size
        wired = (pages[:wired] || 0) * page_size
        compressed = (pages[:compressed] || 0) * page_size
        free = (pages[:free] || 0) * page_size
        speculative = (pages[:speculative] || 0) * page_size
        used = active + wired + compressed

        Stats.new(
          total_bytes: total,
          used_bytes: used,
          free_bytes: free + inactive + speculative,
          active_bytes: active,
          inactive_bytes: inactive,
          wired_bytes: wired,
          compressed_bytes: compressed,
          swap_total_bytes: swap_total,
          swap_used_bytes: swap_used,
          pressure_level: pressure_level,
          pressure_percent: pressure_pct
        )
      end

      private

      def parse_vm_stat
        output = `vm_stat 2>/dev/null`
        page_size = 16384
        if output =~ /page size of (\d+)/
          page_size = $1.to_i
        end

        pages = {}
        output.each_line do |line|
          case line
          when /Pages free:\s+([\d.]+)/           then pages[:free] = $1.to_i
          when /Pages active:\s+([\d.]+)/         then pages[:active] = $1.to_i
          when /Pages inactive:\s+([\d.]+)/       then pages[:inactive] = $1.to_i
          when /Pages speculative:\s+([\d.]+)/    then pages[:speculative] = $1.to_i
          when /Pages wired down:\s+([\d.]+)/     then pages[:wired] = $1.to_i
          when /compressor:\s+([\d.]+)/           then pages[:compressed] = $1.to_i
          end
        end

        [page_size, pages]
      end

      def parse_total_memory
        output = `sysctl -n hw.memsize 2>/dev/null`
        output.strip.to_i
      end

      def parse_swap
        output = `sysctl vm.swapusage 2>/dev/null`
        total = 0
        used = 0
        if output =~ /total\s*=\s*([\d.]+)M/
          total = ($1.to_f * 1024 * 1024).to_i
        end
        if output =~ /used\s*=\s*([\d.]+)M/
          used = ($1.to_f * 1024 * 1024).to_i
        end
        [total, used]
      end

      def parse_pressure
        output = `memory_pressure 2>/dev/null`
        level = "normal"
        pct = 0
        if output =~ /System-wide memory free percentage:\s+(\d+)%/
          free_pct = $1.to_i
          pct = 100 - free_pct
          level = if pct > 80 then "critical"
                  elsif pct > 60 then "warn"
                  else "normal"
                  end
        end
        [level, pct]
      end
    end
  end
end
