module RamObserver
  module UI
    class ExplainPanel
      PANEL_HEIGHT = 7

      def render(screen, y:, text:, pid:)
        width = screen.width

        # Top border
        title = "─ AI Explain: PID #{pid} "
        border = "┌#{title}#{"─" * [width - title.length - 3, 0].max}┐"
        screen.write_line(y, border, color_pair: Screen::COLOR_CYAN)

        # Content lines
        lines = word_wrap(text, [width - 4, 10].max)
        (PANEL_HEIGHT - 2).times do |i|
          content = lines[i] || ""
          padded = content.ljust([width - 4, 0].max)
          line = "│ #{padded} │"
          screen.write_line(y + 1 + i, line, color_pair: Screen::COLOR_CYAN)
        end

        # Bottom border
        hint = " ESC to close "
        pad_total = [width - hint.length - 2, 0].max
        bottom = "└#{"─" * (pad_total / 2)}#{hint}#{"─" * ((pad_total + 1) / 2)}┘"
        screen.write_line(y + PANEL_HEIGHT - 1, bottom[0...width], color_pair: Screen::COLOR_CYAN)
      end

      private

      def word_wrap(text, max_width)
        return [""] if text.nil? || text.empty?
        flat = text.gsub(/\n/, " ")
        lines = []
        while flat.length > max_width
          break_at = flat.rindex(" ", max_width)
          if break_at && break_at > 0
            lines << flat[0...break_at]
            flat = flat[(break_at + 1)..]
          else
            lines << flat[0...max_width]
            flat = flat[max_width..]
          end
        end
        lines << flat unless flat.empty?
        lines.empty? ? [""] : lines
      end
    end
  end
end
