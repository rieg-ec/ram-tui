require "curses"

module RamObserver
  module UI
    class Screen
      COLOR_DEFAULT = 1
      COLOR_HEADER = 2
      COLOR_SELECTED = 3
      COLOR_FROZEN = 4
      COLOR_TREE = 5
      COLOR_DIM = 6
      COLOR_GREEN = 7
      COLOR_YELLOW = 8
      COLOR_RED = 9
      COLOR_CYAN = 10

      attr_reader :width, :height

      def initialize
        Curses.init_screen
        Curses.start_color
        Curses.use_default_colors
        Curses.cbreak
        Curses.noecho
        Curses.curs_set(0)
        Curses.stdscr.keypad(true)
        Curses.stdscr.nodelay = true

        init_colors
        refresh_dimensions
      end

      def close
        Curses.close_screen
      end

      def refresh_dimensions
        @height = Curses.lines
        @width = Curses.cols
      end

      def clear
        Curses.stdscr.clear
      end

      def refresh
        Curses.stdscr.refresh
      end

      def write(y, x, text, color_pair: COLOR_DEFAULT, bold: false, max_width: nil)
        return if y < 0 || y >= @height || x < 0 || x >= @width
        text = text[0...(max_width)] if max_width
        text = text[0...(@width - x)] if x + text.length > @width
        return if text.empty?

        attrs = Curses.color_pair(color_pair)
        attrs |= Curses::A_BOLD if bold
        Curses.stdscr.attron(attrs)
        Curses.stdscr.setpos(y, x)
        Curses.stdscr.addstr(text)
        Curses.stdscr.attroff(attrs)
      end

      def write_line(y, text, color_pair: COLOR_DEFAULT, bold: false)
        padded = text.ljust(@width)[0...@width]
        write(y, 0, padded, color_pair: color_pair, bold: bold)
      end

      def getch
        Curses.stdscr.getch
      end

      private

      def init_colors
        Curses.init_pair(COLOR_DEFAULT, -1, -1)
        Curses.init_pair(COLOR_HEADER, Curses::COLOR_WHITE, Curses::COLOR_BLUE)
        Curses.init_pair(COLOR_SELECTED, Curses::COLOR_WHITE, Curses::COLOR_MAGENTA)
        Curses.init_pair(COLOR_FROZEN, Curses::COLOR_WHITE, Curses::COLOR_RED)
        Curses.init_pair(COLOR_TREE, Curses::COLOR_CYAN, -1)
        Curses.init_pair(COLOR_DIM, Curses::COLOR_WHITE, -1)
        Curses.init_pair(COLOR_GREEN, Curses::COLOR_GREEN, -1)
        Curses.init_pair(COLOR_YELLOW, Curses::COLOR_YELLOW, -1)
        Curses.init_pair(COLOR_RED, Curses::COLOR_RED, -1)
        Curses.init_pair(COLOR_CYAN, Curses::COLOR_CYAN, -1)
      end
    end
  end
end
