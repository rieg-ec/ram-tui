module RamObserver
  module UI
    class StatusBar
      COLUMN_HINTS = {
        "RSS" => "RSS: Physical memory actively used by this process (Resident Set Size)",
        "VIRT" => "VIRT: Total virtual address space including shared libs and memory-mapped files",
        "DIRTY" => "DIRTY: Memory written by the process that can't be reclaimed without swapping to disk",
        "SWAP" => "SWAP: Memory paged out to disk when RAM is full",
        "AGE" => "AGE: Time since the process was launched",
      }.freeze

      def render(screen, mode:, hint_column: nil, search_query: nil, message: nil, selected_entry: nil)
        y = screen.height - 2

        if search_query
          screen.write_line(y, " /#{search_query}█", color_pair: Screen::COLOR_CYAN)
        else
          keys = " ↑↓ Navigate  ←→ Expand  f Freeze  / Search  s Sort  e Explain  x Export  q Quit"
          screen.write_line(y, keys, color_pair: Screen::COLOR_HEADER)
        end

        hint_y = screen.height - 1
        if message
          screen.write_line(hint_y, " #{message}", color_pair: Screen::COLOR_YELLOW)
        elsif selected_entry
          screen.write_line(hint_y, " PID #{selected_entry.pid}: #{selected_entry.command}", color_pair: Screen::COLOR_DIM)
        elsif hint_column && COLUMN_HINTS[hint_column]
          screen.write_line(hint_y, " #{COLUMN_HINTS[hint_column]}", color_pair: Screen::COLOR_DIM)
        else
          screen.write_line(hint_y, "", color_pair: Screen::COLOR_DEFAULT)
        end
      end
    end
  end
end
