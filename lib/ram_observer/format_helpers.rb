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
