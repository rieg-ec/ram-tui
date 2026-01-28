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
