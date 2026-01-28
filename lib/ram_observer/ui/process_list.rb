module RamObserver
  module UI
    class ProcessList
      SPARKLINE_CHARS = "▁▂▃▄▅▆▇█".chars.freeze

      def render(screen, entries:, cursor:, scroll_offset:, list_y:, list_height:, sort_key:, sort_name:, timeline:)
        render_column_header(screen, list_y, sort_name)

        visible_count = [list_height, entries.length - scroll_offset].min
        visible_count = [visible_count, 0].max
        visible_count.times do |i|
          idx = scroll_offset + i
          row = entries[idx]
          next unless row

          y = list_y + 1 + i
          selected = (idx == cursor)
          render_row(screen, y, row, selected, sort_key, timeline)
        end

        # Fill remaining lines
        remaining = list_height - visible_count
        remaining.times do |i|
          screen.write_line(list_y + 1 + visible_count + i, "")
        end

        render_scrollbar(screen, list_y + 1, list_height, scroll_offset, entries.length)
      end

      private

      def render_column_header(screen, y, sort_name)
        cols = format_columns("PID", "NAME", "RSS", "VIRT", "COMP", "SWAP", "AGE", "SPARK")
        # Mark sorted column
        cols = cols.gsub(sort_name, "#{sort_name}↓")
        screen.write_line(y, cols, color_pair: Screen::COLOR_DIM, bold: true)
      end

      def render_row(screen, y, row, selected, sort_key, timeline)
        entry = row[:entry]
        depth = row[:depth]
        prefix = row[:prefix]
        is_last = row[:is_last]

        # Build tree prefix
        tree_str = ""
        if depth > 0
          connector = is_last ? "└─" : "├─"
          tree_str = prefix + connector + " "
        end

        # Expand indicator
        indicator = if entry.leaf?
                      "  "
                    elsif entry.expanded
                      "▼ "
                    else
                      "▶ "
                    end

        h = FormatHelpers
        name = entry.comm_name
        # Truncate name with tree prefix if too long
        max_name_len = 22 - tree_str.length
        max_name_len = [max_name_len, 4].max
        name = name[0...max_name_len] if name.length > max_name_len

        spark = sparkline(timeline[entry.pid])

        line = format_columns(
          entry.pid.to_s,
          "#{tree_str}#{indicator}#{name}",
          h.kb_human(entry.rss_kb),
          h.kb_human(entry.vsz_kb),
          h.bytes_human(entry.compressed_bytes),
          h.bytes_human(entry.swap_bytes),
          entry.age_human,
          spark
        )

        color = if selected
                  Screen::COLOR_SELECTED
                elsif entry.rss_kb > 1_048_576
                  Screen::COLOR_RED
                elsif entry.rss_kb > 524_288
                  Screen::COLOR_YELLOW
                else
                  Screen::COLOR_DEFAULT
                end
        screen.write_line(y, line, color_pair: color)
      end

      def format_columns(pid, name, rss, virt, comp, swap, age, spark)
        " %-7s %-24s %8s %8s %8s %8s %8s  %s" % [pid, name, rss, virt, comp, swap, age, spark]
      end

      def sparkline(data_points)
        return "" unless data_points && data_points.length > 1
        values = data_points.map { |dp| dp[:rss_kb] }
        min_val = values.min.to_f
        max_val = values.max.to_f
        range = max_val - min_val
        return SPARKLINE_CHARS[0] * [values.length, 12].min if range == 0

        # Take last 12 points
        recent = values.last(12)
        recent.map do |v|
          idx = ((v - min_val) / range * (SPARKLINE_CHARS.length - 1)).round
          SPARKLINE_CHARS[idx]
        end.join
      end

      def render_scrollbar(screen, y_start, height, offset, total)
        return if total <= height

        bar_height = [(height.to_f / total * height).ceil, 1].max
        bar_pos = (offset.to_f / total * height).round

        height.times do |i|
          char = (i >= bar_pos && i < bar_pos + bar_height) ? "█" : "│"
          screen.write(y_start + i, screen.width - 1, char, color_pair: Screen::COLOR_DIM)
        end
      end
    end
  end
end
