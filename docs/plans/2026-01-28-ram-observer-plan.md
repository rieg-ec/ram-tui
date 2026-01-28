# ram-observer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a polished Ruby terminal UI for macOS that displays a hierarchical tree of processes with detailed memory metrics (RSS, virtual, compressed, swap), freeze/navigate capability, search, sort, sparkline timelines, export, and on-demand AI explanations via the `claude` CLI.

**Architecture:** Curses-based TUI with a data layer (collectors parse `ps`, `footprint`, `vm_stat`) feeding a process tree model. The UI renders a scrollable tree list with columns, a system header bar, and a status bar. A main event loop handles input and periodic refresh (2s live, paused when frozen). AI explain shells out to `claude --print` with process context.

**Tech Stack:** Ruby 3.2, curses gem, macOS system commands (`ps`, `footprint`, `vm_stat`, `sysctl`, `memory_pressure`), `claude` CLI for AI explanations.

---

### Task 1: Project scaffold and process data collection

**Files:**
- Create: `Gemfile`
- Create: `bin/ram-observer`
- Create: `lib/ram_observer.rb`
- Create: `lib/ram_observer/process_entry.rb`
- Create: `lib/ram_observer/collectors/process_collector.rb`
- Create: `lib/ram_observer/tree_builder.rb`
- Create: `spec/spec_helper.rb`
- Create: `spec/collectors/process_collector_spec.rb`
- Create: `spec/tree_builder_spec.rb`

**Step 1: Create project scaffold**

`Gemfile`:
```ruby
source "https://rubygems.org"

gem "curses", "~> 1.5"

group :development, :test do
  gem "rspec", "~> 3.12"
end
```

`bin/ram-observer`:
```ruby
#!/usr/bin/env ruby
require_relative "../lib/ram_observer"

RamObserver::App.run
```

`lib/ram_observer.rb`:
```ruby
module RamObserver
  autoload :ProcessEntry, "ram_observer/process_entry"
  autoload :TreeBuilder, "ram_observer/tree_builder"
  autoload :App, "ram_observer/app"

  module Collectors
    autoload :ProcessCollector, "ram_observer/collectors/process_collector"
    autoload :MemoryDetail, "ram_observer/collectors/memory_detail"
    autoload :SystemStats, "ram_observer/collectors/system_stats"
  end

  module UI
    autoload :Screen, "ram_observer/ui/screen"
    autoload :Header, "ram_observer/ui/header"
    autoload :ProcessList, "ram_observer/ui/process_list"
    autoload :StatusBar, "ram_observer/ui/status_bar"
    autoload :ExplainPanel, "ram_observer/ui/explain_panel"
    autoload :SearchBar, "ram_observer/ui/search_bar"
  end
end
```

`spec/spec_helper.rb`:
```ruby
require_relative "../lib/ram_observer"

RSpec.configure do |config|
  config.formatter = :documentation
end
```

Run: `cd /Users/rieg/cs/fun/ram-observer && bundle install`
Run: `chmod +x bin/ram-observer`

**Step 2: Write ProcessEntry data class**

`lib/ram_observer/process_entry.rb`:
```ruby
module RamObserver
  class ProcessEntry
    attr_accessor :pid, :ppid, :rss_kb, :vsz_kb, :command, :comm_name,
                  :elapsed, :started, :compressed_bytes, :swap_bytes,
                  :children, :expanded, :depth, :parent

    def initialize(pid:, ppid:, rss_kb:, vsz_kb:, command:, elapsed:, started:)
      @pid = pid
      @ppid = ppid
      @rss_kb = rss_kb
      @vsz_kb = vsz_kb
      @command = command
      @comm_name = File.basename(command.split(/\s+/).first.to_s)
      @elapsed = elapsed
      @started = started
      @compressed_bytes = 0
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
```

**Step 3: Write ProcessCollector**

`lib/ram_observer/collectors/process_collector.rb`:
```ruby
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
      rescue
        nil
      end
    end
  end
end
```

**Step 4: Write TreeBuilder**

`lib/ram_observer/tree_builder.rb`:
```ruby
module RamObserver
  class TreeBuilder
    # Takes flat list of ProcessEntry, returns array of root entries with children populated.
    def build(entries)
      by_pid = {}
      entries.each { |e| by_pid[e.pid] = e }

      roots = []
      entries.each do |entry|
        parent = by_pid[entry.ppid]
        if parent && parent != entry
          entry.parent = parent
          parent.children << entry
        else
          roots << entry
        end
      end

      roots.sort_by { |e| -e.total_rss_kb }
    end

    # Flatten tree into display order respecting expand/collapse state.
    # Returns array of [entry, depth, tree_prefix_string, is_last_child]
    def flatten(roots, sort_key: :rss_kb)
      result = []
      roots.each { |root| flatten_node(root, 0, "", true, result, sort_key) }
      result
    end

    private

    def flatten_node(entry, depth, prefix, is_last, result, sort_key)
      entry.depth = depth
      result << { entry: entry, depth: depth, prefix: prefix, is_last: is_last }

      return unless entry.expanded && !entry.children.empty?

      sorted = sort_children(entry.children, sort_key)
      sorted.each_with_index do |child, i|
        last = (i == sorted.length - 1)
        child_prefix = if depth == 0
                         ""
                       else
                         prefix + (is_last ? "   " : "│  ")
                       end
        flatten_node(child, depth + 1, child_prefix, last, result, sort_key)
      end
    end

    def sort_children(children, sort_key)
      children.sort_by { |c| -(c.send(sort_key) || 0) }
    end
  end
end
```

**Step 5: Write tests**

`spec/collectors/process_collector_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe RamObserver::Collectors::ProcessCollector do
  subject { described_class.new }

  describe "#parse" do
    it "parses ps output into ProcessEntry objects" do
      output = <<~PS
          PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND
            1     0  14784 435241984   45:25 Wed Jan 28 17:21:44 2026     /sbin/launchd
          362     1  16704 435517696   42:01 Wed Jan 28 17:25:08 2026     /usr/libexec/logd
      PS

      entries = subject.parse(output)
      expect(entries.length).to eq(2)

      launchd = entries[0]
      expect(launchd.pid).to eq(1)
      expect(launchd.ppid).to eq(0)
      expect(launchd.rss_kb).to eq(14784)
      expect(launchd.comm_name).to eq("launchd")
      expect(launchd.command).to eq("/sbin/launchd")
      expect(launchd.started).to eq("Wed Jan 28 17:21:44 2026")
    end

    it "handles commands with spaces and arguments" do
      output = <<~PS
          PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND
          364     1  17248 435381360   42:01 Wed Jan 28 17:25:08 2026     /usr/libexec/UserEventAgent (System)
      PS

      entries = subject.parse(output)
      expect(entries[0].command).to eq("/usr/libexec/UserEventAgent (System)")
    end
  end

  describe "#collect" do
    it "returns entries from the real system" do
      entries = subject.collect
      expect(entries).not_to be_empty
      expect(entries.first).to be_a(RamObserver::ProcessEntry)
    end
  end
end
```

`spec/tree_builder_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe RamObserver::TreeBuilder do
  subject { described_class.new }

  def make_entry(pid:, ppid:, rss: 100)
    RamObserver::ProcessEntry.new(
      pid: pid, ppid: ppid, rss_kb: rss, vsz_kb: rss * 2,
      command: "/usr/bin/proc#{pid}", elapsed: "01:00", started: "Wed Jan 28 17:21:44 2026"
    )
  end

  describe "#build" do
    it "builds parent-child relationships" do
      entries = [
        make_entry(pid: 1, ppid: 0, rss: 500),
        make_entry(pid: 10, ppid: 1, rss: 300),
        make_entry(pid: 20, ppid: 1, rss: 200),
        make_entry(pid: 30, ppid: 10, rss: 100),
      ]

      roots = subject.build(entries)
      expect(roots.length).to eq(1)
      expect(roots[0].pid).to eq(1)
      expect(roots[0].children.length).to eq(2)
      expect(roots[0].children.map(&:pid)).to contain_exactly(10, 20)

      child10 = roots[0].children.find { |c| c.pid == 10 }
      expect(child10.children.length).to eq(1)
      expect(child10.children[0].pid).to eq(30)
    end

    it "sorts roots by total RSS descending" do
      entries = [
        make_entry(pid: 1, ppid: 0, rss: 100),
        make_entry(pid: 2, ppid: 0, rss: 500),
      ]

      roots = subject.build(entries)
      expect(roots.map(&:pid)).to eq([2, 1])
    end
  end

  describe "#flatten" do
    it "flattens only expanded nodes" do
      entries = [
        make_entry(pid: 1, ppid: 0, rss: 500),
        make_entry(pid: 10, ppid: 1, rss: 300),
      ]

      roots = subject.build(entries)
      flat = subject.flatten(roots)
      # Only root visible since not expanded
      expect(flat.length).to eq(1)

      roots[0].expanded = true
      flat = subject.flatten(roots)
      expect(flat.length).to eq(2)
      expect(flat[1][:depth]).to eq(1)
    end
  end
end
```

**Step 6: Run tests**

Run: `cd /Users/rieg/cs/fun/ram-observer && bundle exec rspec`
Expected: All tests pass.

**Step 7: Commit**

```bash
git init
git add -A
git commit -m "feat: project scaffold with process collector and tree builder"
```

---

### Task 2: System stats collector

**Files:**
- Create: `lib/ram_observer/collectors/system_stats.rb`
- Create: `spec/collectors/system_stats_spec.rb`

**Step 1: Write SystemStats collector**

`lib/ram_observer/collectors/system_stats.rb`:
```ruby
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
```

**Step 2: Write test**

`spec/collectors/system_stats_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe RamObserver::Collectors::SystemStats do
  subject { described_class.new }

  describe "#collect" do
    it "returns system memory statistics" do
      stats = subject.collect
      expect(stats.total_bytes).to be > 0
      expect(stats.used_bytes).to be > 0
      expect(stats.active_bytes).to be > 0
      expect(stats.pressure_level).to be_a(String)
    end
  end
end
```

**Step 3: Run tests**

Run: `cd /Users/rieg/cs/fun/ram-observer && bundle exec rspec`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: system stats collector (vm_stat, swap, memory pressure)"
```

---

### Task 3: Core TUI framework with header and status bar

**Files:**
- Create: `lib/ram_observer/app.rb`
- Create: `lib/ram_observer/ui/screen.rb`
- Create: `lib/ram_observer/ui/header.rb`
- Create: `lib/ram_observer/ui/status_bar.rb`
- Create: `lib/ram_observer/format_helpers.rb`

**Step 1: Create format helpers**

`lib/ram_observer/format_helpers.rb`:
```ruby
module RamObserver
  module FormatHelpers
    def self.bytes_human(bytes)
      return "0B" if bytes == 0
      units = ["B", "KB", "MB", "GB", "TB"]
      exp = (Math.log(bytes.abs) / Math.log(1024)).to_i
      exp = [exp, units.length - 1].min
      val = bytes.to_f / (1024**exp)
      if val >= 100
        "%.0f%s" % [val, units[exp]]
      elsif val >= 10
        "%.1f%s" % [val, units[exp]]
      else
        "%.1f%s" % [val, units[exp]]
      end
    end

    def self.kb_human(kb)
      bytes_human(kb * 1024)
    end

    def self.pressure_bar(percent, width: 10)
      filled = (percent / 100.0 * width).round
      filled = [filled, width].min
      "█" * filled + "░" * (width - filled)
    end
  end
end
```

Add `autoload :FormatHelpers, "ram_observer/format_helpers"` to `lib/ram_observer.rb`.

**Step 2: Create Screen manager**

`lib/ram_observer/ui/screen.rb`:
```ruby
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
        return if y < 0 || y >= @height || x >= @width
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
```

**Step 3: Create Header**

`lib/ram_observer/ui/header.rb`:
```ruby
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
```

**Step 4: Create StatusBar**

`lib/ram_observer/ui/status_bar.rb`:
```ruby
module RamObserver
  module UI
    class StatusBar
      COLUMN_HINTS = {
        "RSS" => "RSS: Physical memory actively used by this process (Resident Set Size)",
        "VIRT" => "VIRT: Total virtual address space including shared libs and memory-mapped files",
        "COMP" => "COMP: Memory compressed in RAM by macOS to save space without swapping to disk",
        "SWAP" => "SWAP: Memory paged out to disk when RAM is full",
        "AGE" => "AGE: Time since the process was launched",
      }.freeze

      def render(screen, mode:, hint_column: nil, search_query: nil, message: nil)
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
        elsif hint_column && COLUMN_HINTS[hint_column]
          screen.write_line(hint_y, " #{COLUMN_HINTS[hint_column]}", color_pair: Screen::COLOR_DIM)
        else
          screen.write_line(hint_y, "", color_pair: Screen::COLOR_DEFAULT)
        end
      end
    end
  end
end
```

**Step 5: Create App skeleton**

`lib/ram_observer/app.rb`:
```ruby
module RamObserver
  class App
    REFRESH_INTERVAL = 2.0

    def self.run
      new.run
    end

    def initialize
      @screen = UI::Screen.new
      @header = UI::Header.new
      @status_bar = UI::StatusBar.new
      @process_list = UI::ProcessList.new
      @explain_panel = UI::ExplainPanel.new
      @search_bar = UI::SearchBar.new

      @process_collector = Collectors::ProcessCollector.new
      @system_collector = Collectors::SystemStats.new
      @memory_detail = Collectors::MemoryDetail.new
      @tree_builder = TreeBuilder.new

      @frozen = false
      @cursor = 0
      @scroll_offset = 0
      @sort_key = :rss_kb
      @sort_keys = [:rss_kb, :vsz_kb, :compressed_bytes, :swap_bytes, :age_seconds]
      @sort_names = ["RSS", "VIRT", "COMP", "SWAP", "AGE"]
      @sort_index = 0
      @search_mode = false
      @search_query = ""
      @explain_visible = false
      @explain_text = ""
      @explain_pid = nil
      @message = nil
      @message_until = nil
      @timeline = {}

      @roots = []
      @flat_entries = []
      @system_stats = nil
      @last_refresh = Time.at(0)
    end

    def run
      refresh_data
      loop do
        now = Time.now
        if !@frozen && (now - @last_refresh) >= REFRESH_INTERVAL
          refresh_data
        end

        render
        handle_input
        sleep(0.05)
      end
    rescue => e
      @screen.close
      puts "Error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    ensure
      @screen.close
    end

    private

    def refresh_data
      entries = @process_collector.collect
      @roots = @tree_builder.build(entries)
      @system_stats = @system_collector.collect
      record_timeline(entries)
      rebuild_flat_list
      @last_refresh = Time.now
    end

    def rebuild_flat_list
      all_flat = @tree_builder.flatten(@roots, sort_key: @sort_key)
      if @search_query && !@search_query.empty?
        query = @search_query.downcase
        @flat_entries = all_flat.select { |row| row[:entry].comm_name.downcase.include?(query) || row[:entry].command.downcase.include?(query) }
      else
        @flat_entries = all_flat
      end
      @cursor = [[@cursor, @flat_entries.length - 1].min, 0].max
    end

    def render
      @screen.refresh_dimensions
      @screen.clear

      @header.render(@screen, @system_stats, frozen: @frozen)

      list_height = @screen.height - 4 # header(1) + column header(1) + status(2)
      list_height -= (@explain_visible ? 8 : 0)

      current_message = if @message_until && Time.now < @message_until
                          @message
                        else
                          @message = nil
                          nil
                        end

      hint_col = @sort_names[@sort_index]

      @process_list.render(
        @screen,
        entries: @flat_entries,
        cursor: @cursor,
        scroll_offset: @scroll_offset,
        list_y: 1,
        list_height: list_height,
        sort_key: @sort_key,
        sort_name: @sort_names[@sort_index],
        timeline: @timeline
      )

      if @explain_visible
        explain_y = 1 + 1 + list_height
        @explain_panel.render(@screen, y: explain_y, text: @explain_text, pid: @explain_pid)
      end

      @status_bar.render(
        @screen,
        mode: @frozen ? :frozen : :live,
        hint_column: hint_col,
        search_query: @search_mode ? @search_query : nil,
        message: current_message
      )

      @screen.refresh
    end

    def handle_input
      ch = @screen.getch
      return unless ch

      if @search_mode
        handle_search_input(ch)
      elsif @explain_visible
        handle_explain_input(ch)
      else
        handle_normal_input(ch)
      end
    end

    def handle_normal_input(ch)
      case ch
      when Curses::KEY_UP, ?k
        move_cursor(-1)
      when Curses::KEY_DOWN, ?j
        move_cursor(1)
      when Curses::KEY_RIGHT, ?l
        expand_current
      when Curses::KEY_LEFT, ?h
        collapse_current
      when ?f
        @frozen = !@frozen
        flash_message(@frozen ? "View frozen" : "Live updates resumed")
      when ?s
        cycle_sort
      when ?/
        @search_mode = true
        @search_query = ""
      when ?e
        start_explain
      when ?x
        export_snapshot
      when ?q
        raise SystemExit
      end
    end

    def handle_search_input(ch)
      case ch
      when 27 # ESC
        @search_mode = false
        @search_query = ""
        rebuild_flat_list
      when 10, 13 # Enter
        @search_mode = false
      when Curses::KEY_BACKSPACE, 127
        @search_query = @search_query[0...-1]
        rebuild_flat_list
      else
        if ch.is_a?(String) && ch.length == 1 && ch.ord >= 32
          @search_query += ch
          rebuild_flat_list
        end
      end
    end

    def handle_explain_input(ch)
      case ch
      when 27, ?q # ESC or q closes explain
        @explain_visible = false
        @explain_text = ""
      end
    end

    def move_cursor(delta)
      @cursor = [[@cursor + delta, @flat_entries.length - 1].min, 0].max
      # Adjust scroll
      list_height = @screen.height - 4 - (@explain_visible ? 8 : 0)
      if @cursor < @scroll_offset
        @scroll_offset = @cursor
      elsif @cursor >= @scroll_offset + list_height
        @scroll_offset = @cursor - list_height + 1
      end
    end

    def expand_current
      return if @flat_entries.empty?
      entry = @flat_entries[@cursor][:entry]
      unless entry.leaf?
        entry.expanded = true
        rebuild_flat_list
      end
    end

    def collapse_current
      return if @flat_entries.empty?
      entry = @flat_entries[@cursor][:entry]
      if entry.expanded && !entry.leaf?
        entry.expanded = false
        rebuild_flat_list
      elsif entry.parent
        # Jump to parent and collapse it
        entry.parent.expanded = false
        rebuild_flat_list
        idx = @flat_entries.index { |r| r[:entry] == entry.parent }
        @cursor = idx if idx
      end
    end

    def cycle_sort
      @sort_index = (@sort_index + 1) % @sort_keys.length
      @sort_key = @sort_keys[@sort_index]
      rebuild_flat_list
      flash_message("Sorted by #{@sort_names[@sort_index]}")
    end

    def start_explain
      return if @flat_entries.empty?
      entry = @flat_entries[@cursor][:entry]
      @explain_visible = true
      @explain_pid = entry.pid
      @explain_text = "Asking Claude about PID #{entry.pid} (#{entry.comm_name})..."

      Thread.new do
        h = FormatHelpers
        prompt = <<~PROMPT
          You are a macOS process expert. Explain this process concisely (3-4 sentences max).
          What it is, what it does, and why it might be using the memory shown.

          Process: #{entry.comm_name}
          Full command: #{entry.command}
          PID: #{entry.pid}, Parent PID: #{entry.ppid}
          RSS: #{h.kb_human(entry.rss_kb)}, Virtual: #{h.kb_human(entry.vsz_kb)}
          Compressed: #{h.bytes_human(entry.compressed_bytes)}, Swap: #{h.bytes_human(entry.swap_bytes)}
          Age: #{entry.age_human}
          Parent chain: #{parent_chain(entry)}
        PROMPT

        result = `claude --print "#{prompt.gsub('"', '\\"')}" 2>/dev/null`
        @explain_text = result.strip.empty? ? "No explanation available." : result.strip
      rescue => e
        @explain_text = "Error: #{e.message}"
      end
    end

    def parent_chain(entry)
      chain = []
      current = entry.parent
      while current
        chain << current.comm_name
        current = current.parent
      end
      chain.reverse.join(" > ")
    end

    def export_snapshot
      require "json"
      timestamp = Time.now.strftime("%Y-%m-%d-%H%M%S")
      filename = "ram-snapshot-#{timestamp}.json"

      data = {
        timestamp: Time.now.iso8601,
        system: @system_stats&.to_h,
        processes: @flat_entries.map do |row|
          e = row[:entry]
          {
            pid: e.pid, ppid: e.ppid, name: e.comm_name,
            command: e.command, rss_kb: e.rss_kb, vsz_kb: e.vsz_kb,
            compressed_bytes: e.compressed_bytes, swap_bytes: e.swap_bytes,
            age: e.age_human, started: e.started, depth: row[:depth]
          }
        end
      }

      File.write(filename, JSON.pretty_generate(data))
      flash_message("Exported to #{filename}")
    end

    def record_timeline(entries)
      now = Time.now
      entries.each do |e|
        @timeline[e.pid] ||= []
        @timeline[e.pid] << { time: now, rss_kb: e.rss_kb }
        # Keep only last 60 data points (2 minutes at 2s refresh)
        @timeline[e.pid] = @timeline[e.pid].last(60)
      end
      # Clean dead PIDs
      live_pids = entries.map(&:pid).to_set
      @timeline.delete_if { |pid, _| !live_pids.include?(pid) }
    end

    def flash_message(msg)
      @message = msg
      @message_until = Time.now + 2
    end
  end
end
```

Add `require "set"` at the top of `lib/ram_observer.rb`.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: core TUI framework with header, status bar, and app loop"
```

---

### Task 4: Process list rendering with tree columns and sparklines

**Files:**
- Create: `lib/ram_observer/ui/process_list.rb`

**Step 1: Write ProcessList view**

`lib/ram_observer/ui/process_list.rb`:
```ruby
module RamObserver
  module UI
    class ProcessList
      SPARKLINE_CHARS = "▁▂▃▄▅▆▇█".chars.freeze

      def render(screen, entries:, cursor:, scroll_offset:, list_y:, list_height:, sort_key:, sort_name:, timeline:)
        render_column_header(screen, list_y, sort_name)

        visible_count = [list_height, entries.length - scroll_offset].min
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

        color = selected ? Screen::COLOR_SELECTED : Screen::COLOR_DEFAULT
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
```

**Step 2: Commit**

```bash
git add -A
git commit -m "feat: process list view with tree rendering, columns, and sparklines"
```

---

### Task 5: Explain panel and memory detail collector

**Files:**
- Create: `lib/ram_observer/ui/explain_panel.rb`
- Create: `lib/ram_observer/collectors/memory_detail.rb`
- Create: `lib/ram_observer/ui/search_bar.rb`

**Step 1: Write ExplainPanel**

`lib/ram_observer/ui/explain_panel.rb`:
```ruby
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
        lines = word_wrap(text, width - 4)
        (PANEL_HEIGHT - 2).times do |i|
          content = lines[i] || ""
          line = "│ #{content.ljust(width - 4)} │"
          screen.write_line(y + 1 + i, line, color_pair: Screen::COLOR_CYAN)
        end

        # Bottom border
        hint = " ESC to close "
        bottom = "└#{"─" * ((width - hint.length - 2) / 2)}#{hint}#{"─" * ((width - hint.length - 2 + 1) / 2)}┘"
        screen.write_line(y + PANEL_HEIGHT - 1, bottom[0...width], color_pair: Screen::COLOR_CYAN)
      end

      private

      def word_wrap(text, max_width)
        text.gsub(/\n/, " ").scan(/.{1,#{max_width}}(?:\s|\Z)/).map(&:strip)
      end
    end
  end
end
```

**Step 2: Write SearchBar (simple — integrated into status bar, but need the module)**

`lib/ram_observer/ui/search_bar.rb`:
```ruby
module RamObserver
  module UI
    class SearchBar
      # Search is handled inline in StatusBar and App.
      # This exists to satisfy the autoload.
    end
  end
end
```

**Step 3: Write MemoryDetail collector**

`lib/ram_observer/collectors/memory_detail.rb`:
```ruby
module RamObserver
  module Collectors
    class MemoryDetail
      # Fetches per-process compressed and swap memory using footprint.
      # This is expensive, so we only call it for visible processes.

      def collect_for(pid)
        output = `footprint #{pid} 2>/dev/null`
        parse_footprint(output)
      rescue
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

        # footprint output has a summary line like:
        # "Footprint: 183 MB" and detailed category lines
        # We look for the "TOTAL" or overall dirty/swapped numbers
        output.each_line do |line|
          # Look for compressed and swapped in the summary
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
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: explain panel, memory detail collector, search bar"
```

---

### Task 6: Integration and polish

**Files:**
- Modify: `lib/ram_observer/app.rb` — integrate memory detail enrichment for visible processes
- Modify: `lib/ram_observer.rb` — ensure all requires

**Step 1: Add memory detail enrichment to the refresh cycle**

In `App#refresh_data`, after building the flat list, enrich visible processes:

```ruby
def refresh_data
  entries = @process_collector.collect
  @roots = @tree_builder.build(entries)
  @system_stats = @system_collector.collect
  record_timeline(entries)
  rebuild_flat_list
  enrich_visible_memory
  @last_refresh = Time.now
end

def enrich_visible_memory
  return if @flat_entries.empty?
  list_height = @screen.height - 4
  visible_start = @scroll_offset
  visible_end = [@scroll_offset + list_height, @flat_entries.length].min
  visible_pids = @flat_entries[visible_start...visible_end].map { |r| r[:entry].pid }

  # Only enrich top 10 visible to keep it fast
  top_pids = visible_pids.first(10)
  Thread.new do
    top_pids.each do |pid|
      detail = @memory_detail.collect_for(pid)
      entry = @flat_entries.find { |r| r[:entry].pid == pid }&.dig(:entry)
      next unless entry
      entry.compressed_bytes = detail[:compressed]
      entry.swap_bytes = detail[:swap]
    end
  end
end
```

**Step 2: Final require setup in `lib/ram_observer.rb`**

```ruby
require "set"

module RamObserver
  autoload :ProcessEntry, "ram_observer/process_entry"
  autoload :TreeBuilder, "ram_observer/tree_builder"
  autoload :FormatHelpers, "ram_observer/format_helpers"
  autoload :App, "ram_observer/app"

  module Collectors
    autoload :ProcessCollector, "ram_observer/collectors/process_collector"
    autoload :MemoryDetail, "ram_observer/collectors/memory_detail"
    autoload :SystemStats, "ram_observer/collectors/system_stats"
  end

  module UI
    autoload :Screen, "ram_observer/ui/screen"
    autoload :Header, "ram_observer/ui/header"
    autoload :ProcessList, "ram_observer/ui/process_list"
    autoload :StatusBar, "ram_observer/ui/status_bar"
    autoload :ExplainPanel, "ram_observer/ui/explain_panel"
    autoload :SearchBar, "ram_observer/ui/search_bar"
  end
end
```

**Step 3: Run the app manually**

Run: `cd /Users/rieg/cs/fun/ram-observer && ruby bin/ram-observer`
Verify: TUI appears with system header, process tree, keybindings work.

**Step 4: Run all tests**

Run: `cd /Users/rieg/cs/fun/ram-observer && bundle exec rspec`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: integrate memory detail enrichment and finalize all components"
```

---

### Task 7: Final polish — colors, resize handling, edge cases

**Step 1: Handle terminal resize**

In `App#handle_input`, add `Curses::KEY_RESIZE` handling:

```ruby
when Curses::KEY_RESIZE
  @screen.refresh_dimensions
```

**Step 2: Add color coding for memory values**

In `ProcessList#render_row`, after writing the main line, optionally color-code high-memory processes (RSS > 1GB = red, > 500MB = yellow).

**Step 3: Handle empty process list gracefully**

Ensure cursor operations are no-ops when `@flat_entries` is empty.

**Step 4: Ensure `claude` CLI prompt uses proper escaping**

In `App#start_explain`, use a tempfile for the prompt to avoid shell escaping issues:

```ruby
require "tempfile"

def start_explain
  return if @flat_entries.empty?
  entry = @flat_entries[@cursor][:entry]
  @explain_visible = true
  @explain_pid = entry.pid
  @explain_text = "Asking Claude about PID #{entry.pid} (#{entry.comm_name})..."

  Thread.new do
    h = FormatHelpers
    prompt = <<~PROMPT
      You are a macOS process expert. Explain this process concisely (3-4 sentences max).
      What it is, what it does, and why it might be using the memory shown.

      Process: #{entry.comm_name}
      Full command: #{entry.command}
      PID: #{entry.pid}, Parent PID: #{entry.ppid}
      RSS: #{h.kb_human(entry.rss_kb)}, Virtual: #{h.kb_human(entry.vsz_kb)}
      Compressed: #{h.bytes_human(entry.compressed_bytes)}, Swap: #{h.bytes_human(entry.swap_bytes)}
      Age: #{entry.age_human}
      Parent chain: #{parent_chain(entry)}
    PROMPT

    tmpfile = Tempfile.new(["ram-observer-prompt", ".txt"])
    tmpfile.write(prompt)
    tmpfile.close

    result = `cat "#{tmpfile.path}" | claude --print 2>/dev/null`
    @explain_text = result.strip.empty? ? "No explanation available." : result.strip
  rescue => e
    @explain_text = "Error: #{e.message}"
  ensure
    tmpfile&.unlink
  end
end
```

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat: polish — resize handling, color coding, safe claude invocation"
```

---

### Task 8: Comprehensive RSpec test suite

**Files:**
- Create: `spec/process_entry_spec.rb`
- Create: `spec/format_helpers_spec.rb`
- Create: `spec/collectors/memory_detail_spec.rb`
- Modify: `spec/tree_builder_spec.rb` — add edge case tests
- Modify: `spec/collectors/process_collector_spec.rb` — add edge case tests

**Step 1: Write ProcessEntry tests**

`spec/process_entry_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe RamObserver::ProcessEntry do
  def make_entry(overrides = {})
    defaults = {
      pid: 100, ppid: 1, rss_kb: 1024, vsz_kb: 4096,
      command: "/usr/bin/test --flag", elapsed: "1-02:30:45",
      started: "Wed Jan 28 17:21:44 2026"
    }
    described_class.new(**defaults.merge(overrides))
  end

  describe "#comm_name" do
    it "extracts basename from command path" do
      entry = make_entry(command: "/usr/local/bin/node server.js")
      expect(entry.comm_name).to eq("node")
    end

    it "handles command with no path" do
      entry = make_entry(command: "ruby script.rb")
      expect(entry.comm_name).to eq("ruby")
    end

    it "handles parenthesized commands" do
      entry = make_entry(command: "/usr/libexec/UserEventAgent (System)")
      expect(entry.comm_name).to eq("UserEventAgent")
    end
  end

  describe "#rss_bytes" do
    it "converts KB to bytes" do
      entry = make_entry(rss_kb: 1024)
      expect(entry.rss_bytes).to eq(1024 * 1024)
    end
  end

  describe "#age_human" do
    it "formats seconds" do
      entry = make_entry(elapsed: "00:30")
      expect(entry.age_human).to eq("30s")
    end

    it "formats minutes" do
      entry = make_entry(elapsed: "05:30")
      expect(entry.age_human).to eq("5m")
    end

    it "formats hours and minutes" do
      entry = make_entry(elapsed: "02:30:00")
      expect(entry.age_human).to eq("2h 30m")
    end

    it "formats days and hours" do
      entry = make_entry(elapsed: "3-04:30:00")
      expect(entry.age_human).to eq("3d 4h")
    end
  end

  describe "#total_rss_kb" do
    it "sums self and children RSS" do
      parent = make_entry(rss_kb: 500)
      child1 = make_entry(rss_kb: 200)
      child2 = make_entry(rss_kb: 300)
      parent.children = [child1, child2]
      expect(parent.total_rss_kb).to eq(1000)
    end

    it "includes nested children" do
      root = make_entry(rss_kb: 100)
      child = make_entry(rss_kb: 200)
      grandchild = make_entry(rss_kb: 300)
      child.children = [grandchild]
      root.children = [child]
      expect(root.total_rss_kb).to eq(600)
    end
  end

  describe "#leaf?" do
    it "returns true when no children" do
      expect(make_entry.leaf?).to be true
    end

    it "returns false when has children" do
      entry = make_entry
      entry.children = [make_entry]
      expect(entry.leaf?).to be false
    end
  end
end
```

**Step 2: Write FormatHelpers tests**

`spec/format_helpers_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe RamObserver::FormatHelpers do
  describe ".bytes_human" do
    it "formats zero" do
      expect(described_class.bytes_human(0)).to eq("0B")
    end

    it "formats bytes" do
      expect(described_class.bytes_human(512)).to eq("512B")
    end

    it "formats kilobytes" do
      expect(described_class.bytes_human(2048)).to eq("2.0KB")
    end

    it "formats megabytes" do
      expect(described_class.bytes_human(500 * 1024 * 1024)).to eq("500MB")
    end

    it "formats gigabytes" do
      expect(described_class.bytes_human(2.5 * 1024 * 1024 * 1024)).to eq("2.5GB")
    end

    it "formats large gigabytes" do
      expect(described_class.bytes_human(18 * 1024 * 1024 * 1024)).to eq("18.0GB")
    end
  end

  describe ".kb_human" do
    it "converts KB to human readable" do
      expect(described_class.kb_human(1024)).to eq("1.0MB")
    end
  end

  describe ".pressure_bar" do
    it "shows empty bar at 0%" do
      bar = described_class.pressure_bar(0, width: 5)
      expect(bar).to eq("░░░░░")
    end

    it "shows full bar at 100%" do
      bar = described_class.pressure_bar(100, width: 5)
      expect(bar).to eq("█████")
    end

    it "shows half bar at 50%" do
      bar = described_class.pressure_bar(50, width: 10)
      expect(bar.count("█")).to eq(5)
      expect(bar.count("░")).to eq(5)
    end
  end
end
```

**Step 3: Write MemoryDetail tests**

`spec/collectors/memory_detail_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe RamObserver::Collectors::MemoryDetail do
  subject { described_class.new }

  describe "#collect_for" do
    it "returns a hash with compressed and swap keys" do
      # Use PID 1 (launchd) which always exists
      result = subject.collect_for(1)
      expect(result).to have_key(:compressed)
      expect(result).to have_key(:swap)
      expect(result[:compressed]).to be_a(Integer)
      expect(result[:swap]).to be_a(Integer)
    end

    it "returns zeros for non-existent PID" do
      result = subject.collect_for(999999)
      expect(result[:compressed]).to eq(0)
      expect(result[:swap]).to eq(0)
    end
  end
end
```

**Step 4: Add edge cases to existing tree_builder_spec.rb**

Append to `spec/tree_builder_spec.rb`:
```ruby
  describe "#build edge cases" do
    it "handles orphan processes (ppid points to non-existent parent)" do
      entries = [
        make_entry(pid: 10, ppid: 999, rss: 300),
        make_entry(pid: 20, ppid: 999, rss: 200),
      ]
      roots = subject.build(entries)
      expect(roots.length).to eq(2)
    end

    it "handles self-referencing ppid" do
      entries = [make_entry(pid: 1, ppid: 1, rss: 500)]
      roots = subject.build(entries)
      expect(roots.length).to eq(1)
      expect(roots[0].children).to be_empty
    end

    it "handles empty input" do
      roots = subject.build([])
      expect(roots).to eq([])
    end
  end

  describe "#flatten edge cases" do
    it "handles empty roots" do
      flat = subject.flatten([])
      expect(flat).to eq([])
    end

    it "deeply nested tree flattens correctly when all expanded" do
      entries = [
        make_entry(pid: 1, ppid: 0, rss: 400),
        make_entry(pid: 2, ppid: 1, rss: 300),
        make_entry(pid: 3, ppid: 2, rss: 200),
        make_entry(pid: 4, ppid: 3, rss: 100),
      ]
      roots = subject.build(entries)
      # Expand all
      roots[0].expanded = true
      roots[0].children[0].expanded = true
      roots[0].children[0].children[0].expanded = true

      flat = subject.flatten(roots)
      expect(flat.length).to eq(4)
      expect(flat.map { |r| r[:depth] }).to eq([0, 1, 2, 3])
    end
  end
```

**Step 5: Add edge cases to process_collector_spec.rb**

Append to `spec/collectors/process_collector_spec.rb`:
```ruby
  describe "#parse edge cases" do
    it "handles empty output" do
      entries = subject.parse("")
      expect(entries).to eq([])
    end

    it "handles header-only output" do
      output = "  PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND\n"
      entries = subject.parse(output)
      expect(entries).to eq([])
    end

    it "handles malformed lines gracefully" do
      output = <<~PS
          PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND
          bad line
            1     0  14784 435241984   45:25 Wed Jan 28 17:21:44 2026     /sbin/launchd
      PS
      entries = subject.parse(output)
      expect(entries.length).to eq(1)
      expect(entries[0].pid).to eq(1)
    end
  end
```

**Step 6: Run all tests**

Run: `cd /Users/rieg/cs/fun/ram-observer && bundle exec rspec --format documentation`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add -A
git commit -m "test: comprehensive RSpec suite for all data layer components"
```

---

### Task 9: Bug-finding and stabilization loop

This task is different from the others. The agent should:

1. **Launch the app** in a way that exercises it programmatically (since the TUI can't be interacted with from a subagent, test via unit tests and code review).
2. **Run the full test suite** and fix any failures.
3. **Review every file** for common bugs: off-by-one errors, nil safety, thread safety, encoding issues with Unicode box-drawing chars, curses edge cases (writing past screen bounds), division by zero in sparklines/pressure bar.
4. **Attempt to load and instantiate** every class in a non-curses context to catch require/autoload issues.
5. **Fix all bugs found**, re-run tests after each fix.
6. **Repeat** until a full review pass finds zero issues.

**Step 1: Write a smoke test that loads all classes**

Create `spec/smoke_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe "Smoke test" do
  it "loads all data layer classes without error" do
    expect { RamObserver::ProcessEntry }.not_to raise_error
    expect { RamObserver::TreeBuilder }.not_to raise_error
    expect { RamObserver::FormatHelpers }.not_to raise_error
    expect { RamObserver::Collectors::ProcessCollector }.not_to raise_error
    expect { RamObserver::Collectors::MemoryDetail }.not_to raise_error
    expect { RamObserver::Collectors::SystemStats }.not_to raise_error
  end

  it "collects real process data and builds a tree" do
    collector = RamObserver::Collectors::ProcessCollector.new
    entries = collector.collect
    expect(entries.length).to be > 10

    builder = RamObserver::TreeBuilder.new
    roots = builder.build(entries)
    expect(roots.length).to be > 0

    # Expand first root and flatten
    roots.first.expanded = true
    flat = builder.flatten(roots)
    expect(flat.length).to be > 1
  end

  it "collects system stats" do
    stats = RamObserver::Collectors::SystemStats.new.collect
    expect(stats.total_bytes).to be > 1_000_000_000 # at least 1GB
    expect(stats.pressure_level).to match(/normal|warn|critical/)
  end

  it "formats all memory values without error" do
    h = RamObserver::FormatHelpers
    [0, 1, 1023, 1024, 1024*1024, 1024*1024*1024, 1024*1024*1024*20].each do |bytes|
      expect { h.bytes_human(bytes) }.not_to raise_error
      result = h.bytes_human(bytes)
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end
  end
end
```

**Step 2: Run full test suite**

Run: `cd /Users/rieg/cs/fun/ram-observer && bundle exec rspec --format documentation`

**Step 3: Code review pass — check every file for bugs**

Review these specific categories:
- `process_list.rb`: Does `format_columns` handle names longer than 24 chars? Does `visible_count` go negative? Does sparkline handle single data point?
- `app.rb`: Thread safety — `@flat_entries` and `@explain_text` mutated from threads. `move_cursor` when `@flat_entries` is empty. `record_timeline` with `to_set` — is `require "set"` loaded?
- `tree_builder.rb`: Does `sort_children` crash if `sort_key` returns nil?
- `screen.rb`: Does `write` crash if text contains multibyte Unicode chars (box drawing) that exceed column width?
- `header.rb`: Does it crash if `stats` values are zero?
- `explain_panel.rb`: Does `word_wrap` handle very long words without spaces?
- `format_helpers.rb`: Does `bytes_human` handle negative values?

**Step 4: Fix all found bugs, write regression tests for each**

**Step 5: Run tests again**

Run: `cd /Users/rieg/cs/fun/ram-observer && bundle exec rspec --format documentation`
Expected: All pass.

**Step 6: Repeat Steps 3-5 until clean**

**Step 7: Commit**

```bash
git add -A
git commit -m "fix: bug fixes from stabilization review pass"
```
