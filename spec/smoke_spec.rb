require "spec_helper"

RSpec.describe "Smoke tests" do
  describe "class loading" do
    it "loads all data layer classes without error" do
      expect { RamObserver::ProcessEntry }.not_to raise_error
      expect { RamObserver::TreeBuilder }.not_to raise_error
      expect { RamObserver::FormatHelpers }.not_to raise_error
      expect { RamObserver::Collectors::ProcessCollector }.not_to raise_error
      expect { RamObserver::Collectors::SystemStats }.not_to raise_error
      expect { RamObserver::Collectors::MemoryDetail }.not_to raise_error
    end
  end

  describe "end-to-end process tree" do
    it "collects real process data, builds tree, expands first root, and flattens" do
      collector = RamObserver::Collectors::ProcessCollector.new
      entries = collector.collect
      expect(entries).not_to be_empty

      builder = RamObserver::TreeBuilder.new
      roots = builder.build(entries)
      expect(roots).not_to be_empty

      roots.first.expanded = true
      flat = builder.flatten(roots)
      expect(flat.length).to be > 1
    end
  end

  describe "system stats" do
    it "returns total_bytes > 1GB and a valid pressure_level" do
      stats = RamObserver::Collectors::SystemStats.new.collect
      one_gb = 1024 * 1024 * 1024
      expect(stats.total_bytes).to be > one_gb
      expect(%w[normal warn critical]).to include(stats.pressure_level)
    end
  end

  describe "FormatHelpers robustness" do
    it "does not error on various byte values" do
      values = [0, 1, 1023, 1024, 1024 * 1024, 1024 * 1024 * 1024, 1024 * 1024 * 1024 * 20]
      values.each do |v|
        expect { RamObserver::FormatHelpers.bytes_human(v) }.not_to raise_error
        result = RamObserver::FormatHelpers.bytes_human(v)
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end
  end
end
