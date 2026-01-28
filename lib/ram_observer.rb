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
