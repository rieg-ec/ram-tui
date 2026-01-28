require "spec_helper"

RSpec.describe RamObserver::FormatHelpers do
  describe ".bytes_human" do
    it "formats 0 as 0B" do
      expect(described_class.bytes_human(0)).to eq("0B")
    end

    it "formats 512 as 512B" do
      expect(described_class.bytes_human(512)).to eq("512B")
    end

    it "formats 2048 as 2.0KB" do
      expect(described_class.bytes_human(2048)).to eq("2.0KB")
    end

    it "formats 500MB correctly" do
      expect(described_class.bytes_human(500 * 1024 * 1024)).to eq("500MB")
    end

    it "formats 2.5GB correctly" do
      expect(described_class.bytes_human((2.5 * 1024 * 1024 * 1024).to_i)).to eq("2.5GB")
    end

    it "formats 18GB correctly" do
      expect(described_class.bytes_human(18 * 1024 * 1024 * 1024)).to eq("18.0GB")
    end
  end

  describe ".kb_human" do
    it "converts KB to human readable" do
      expect(described_class.kb_human(1024)).to eq("1.0MB")
    end
  end

  describe ".pressure_bar" do
    it "returns all empty for 0%" do
      bar = described_class.pressure_bar(0)
      expect(bar).to eq("░" * 10)
    end

    it "returns all filled for 100%" do
      bar = described_class.pressure_bar(100)
      expect(bar).to eq("█" * 10)
    end

    it "returns half and half for 50%" do
      bar = described_class.pressure_bar(50)
      expect(bar).to eq("█" * 5 + "░" * 5)
    end
  end
end
