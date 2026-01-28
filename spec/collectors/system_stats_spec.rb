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
