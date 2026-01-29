require "set"
require "tempfile"

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

      @process_collector = Collectors::ProcessCollector.new
      @system_collector = Collectors::SystemStats.new
      @memory_detail = Collectors::MemoryDetail.new
      @tree_builder = TreeBuilder.new

      @frozen = false
      @cursor = 0
      @scroll_offset = 0
      @sort_key = :rss_kb
      @sort_keys = [:rss_kb, :vsz_kb, :dirty_bytes, :swap_bytes, :age_seconds]
      @sort_names = ["RSS", "VIRT", "DIRTY", "SWAP", "AGE"]
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
      @enrich_thread = nil
      @last_enrich = Time.at(0)
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
    rescue SystemExit, Interrupt
      # Clean exit
    rescue => e
      @screen.close
      puts "Error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    ensure
      @screen.close
    end

    private

    def refresh_data
      expanded_pids = collect_expanded_pids(@roots)
      entries = @process_collector.collect
      @roots = @tree_builder.build(entries)
      restore_expanded(@roots, expanded_pids)
      @system_stats = @system_collector.collect
      record_timeline(entries)
      rebuild_flat_list
      enrich_visible_memory
      @last_refresh = Time.now
    end

    def collect_expanded_pids(nodes)
      pids = Set.new
      nodes.each do |node|
        pids.add(node.pid) if node.expanded
        pids.merge(collect_expanded_pids(node.children))
      end
      pids
    end

    def restore_expanded(nodes, pids)
      nodes.each do |node|
        node.expanded = true if pids.include?(node.pid)
        restore_expanded(node.children, pids)
      end
    end

    def enrich_visible_memory
      return if @flat_entries.empty?
      return if @enrich_thread&.alive?
      return if (Time.now - @last_enrich) < 10

      list_height = [@screen.height - 4, 0].max
      visible_start = @scroll_offset
      visible_end = [@scroll_offset + list_height, @flat_entries.length].min
      visible_pids = (@flat_entries[visible_start...visible_end] || []).map { |r| r[:entry].pid }

      top_pids = visible_pids.first(5)
      flat_snapshot = @flat_entries
      @last_enrich = Time.now
      @enrich_thread = Thread.new do
        top_pids.each do |pid|
          detail = @memory_detail.collect_for(pid)
          entry = flat_snapshot.find { |r| r[:entry].pid == pid }&.dig(:entry)
          next unless entry
          entry.dirty_bytes = detail[:dirty]
          entry.swap_bytes = detail[:swap]
          sleep(0.5)
        end
      end
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

      @header.render(@screen, @system_stats, frozen: @frozen)

      list_height = @screen.height - 4
      list_height -= (@explain_visible ? 8 : 0)
      list_height = [list_height, 0].max

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

      selected = @flat_entries[@cursor]&.dig(:entry)
      @status_bar.render(
        @screen,
        mode: @frozen ? :frozen : :live,
        hint_column: hint_col,
        search_query: @search_mode ? @search_query : nil,
        message: current_message,
        selected_entry: selected
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
      when Curses::KEY_RESIZE
        @screen.refresh_dimensions
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
      when 27, ?q
        @explain_visible = false
        @explain_text = ""
      end
    end

    def move_cursor(delta)
      return if @flat_entries.empty?
      @cursor = [[@cursor + delta, @flat_entries.length - 1].min, 0].max
      list_height = [(@screen.height - 4 - (@explain_visible ? 8 : 0)), 1].max
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
          Dirty: #{h.bytes_human(entry.dirty_bytes)}, Swap: #{h.bytes_human(entry.swap_bytes)}
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

    def parent_chain(entry)
      chain = []
      visited = Set.new
      current = entry.parent
      while current && !visited.include?(current.pid)
        visited << current.pid
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
            dirty_bytes: e.dirty_bytes, swap_bytes: e.swap_bytes,
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
        @timeline[e.pid] = @timeline[e.pid].last(60)
      end
      live_pids = entries.map(&:pid).to_set
      @timeline.delete_if { |pid, _| !live_pids.include?(pid) }
    end

    def flash_message(msg)
      @message = msg
      @message_until = Time.now + 2
    end
  end
end
