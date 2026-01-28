module RamObserver
  module UI
    class Header
      def render(screen, stats, frozen:)
        return unless stats

        h = FormatHelpers
        total = h.bytes_human(stats.total_bytes)
        used = h.bytes_human(stats.used_bytes)
        swap = h.bytes_human(stats.swap_used_bytes)
        bar = h.pressure_bar(stats.pressure_percent, width: 8)

        status = frozen ? " FROZEN " : "  LIVE  "
        status_color = frozen ? Screen::COLOR_FROZEN : Screen::COLOR_HEADER

        line = " RAM: #{used}/#{total}  Swap: #{swap}  Pressure: #{bar} #{stats.pressure_percent}%"
        screen.write_line(0, line, color_pair: Screen::COLOR_HEADER, bold: true)

        # Status badge on the right
        badge_x = screen.width - status.length - 1
        screen.write(0, badge_x, status, color_pair: status_color, bold: true)
      end
    end
  end
end
