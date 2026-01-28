require "spec_helper"

RSpec.describe RamObserver::UI::ProcessList do
  subject { described_class.new }

  describe "#sparkline (via send)" do
    def sparkline(data_points)
      subject.send(:sparkline, data_points)
    end

    it "returns empty string for nil" do
      expect(sparkline(nil)).to eq("")
    end

    it "returns empty string for single data point" do
      expect(sparkline([{ rss_kb: 100 }])).to eq("")
    end

    it "returns flat sparkline when all values are equal" do
      points = 20.times.map { |i| { rss_kb: 100 } }
      result = sparkline(points)
      expect(result.length).to eq(12)
      expect(result.chars.uniq).to eq(["\u2581"]) # all lowest char
    end

    it "caps flat sparkline length at 12 even with more data points" do
      points = 30.times.map { |i| { rss_kb: 100 } }
      result = sparkline(points)
      expect(result.length).to eq(12)
    end

    it "returns rising sparkline for increasing values" do
      points = (1..12).map { |i| { rss_kb: i * 100 } }
      result = sparkline(points)
      expect(result.length).to eq(12)
      expect(result.chars.first).to eq("\u2581")
      expect(result.chars.last).to eq("\u2588")
    end

    it "uses last 12 points for display" do
      points = (1..20).map { |i| { rss_kb: i * 100 } }
      result = sparkline(points)
      expect(result.length).to eq(12)
    end
  end
end
