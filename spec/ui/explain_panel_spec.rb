require "spec_helper"

RSpec.describe RamObserver::UI::ExplainPanel do
  subject { described_class.new }

  describe "#word_wrap (via send)" do
    def wrap(text, width)
      subject.send(:word_wrap, text, width)
    end

    it "returns empty string array for nil text" do
      expect(wrap(nil, 20)).to eq([""])
    end

    it "returns empty string array for empty text" do
      expect(wrap("", 20)).to eq([""])
    end

    it "returns single line for short text" do
      expect(wrap("hello", 20)).to eq(["hello"])
    end

    it "wraps at word boundaries" do
      lines = wrap("hello world foo bar", 11)
      expect(lines).to eq(["hello world", "foo bar"])
    end

    it "handles words longer than max_width without dropping characters" do
      long_word = "a" * 50
      lines = wrap(long_word, 20)
      expect(lines.join.length).to eq(50)
      expect(lines[0].length).to eq(20)
      expect(lines[1].length).to eq(20)
      expect(lines[2].length).to eq(10)
    end

    it "converts newlines to spaces" do
      lines = wrap("hello\nworld", 20)
      expect(lines).to eq(["hello world"])
    end
  end
end
