require "spec_helper"

RSpec.describe RamObserver::Collectors::MemoryDetail do
  subject { described_class.new }

  describe "#collect_for" do
    it "returns hash with :compressed and :swap keys for PID 1 (launchd)" do
      result = subject.collect_for(1)
      expect(result).to be_a(Hash)
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
