require "spec_helper"

RSpec.describe RamObserver::ProcessEntry do
  def make_entry(overrides = {})
    defaults = {
      pid: 42, ppid: 1, rss_kb: 1024, vsz_kb: 2048,
      command: "/usr/local/bin/node server.js",
      elapsed: "01:00", started: "Wed Jan 28 17:21:44 2026"
    }
    described_class.new(**defaults.merge(overrides))
  end

  describe "#comm_name" do
    it "extracts basename from absolute path command" do
      entry = make_entry(command: "/usr/local/bin/node server.js")
      expect(entry.comm_name).to eq("node")
    end

    it "extracts first word when there is no path" do
      entry = make_entry(command: "ruby script.rb")
      expect(entry.comm_name).to eq("ruby")
    end

    it "extracts basename from parenthesized command" do
      entry = make_entry(command: "/usr/libexec/UserEventAgent (System)")
      expect(entry.comm_name).to eq("UserEventAgent")
    end

    it "handles single word command with no arguments" do
      entry = make_entry(command: "launchd")
      expect(entry.comm_name).to eq("launchd")
    end
  end

  describe "#rss_bytes" do
    it "converts KB to bytes" do
      entry = make_entry(rss_kb: 256)
      expect(entry.rss_bytes).to eq(256 * 1024)
    end
  end

  describe "#age_human" do
    it "returns seconds for <60s" do
      entry = make_entry(elapsed: "00:30")
      expect(entry.age_human).to eq("30s")
    end

    it "returns minutes for <60m" do
      entry = make_entry(elapsed: "05:30")
      expect(entry.age_human).to eq("5m")
    end

    it "returns hours and minutes for <24h" do
      entry = make_entry(elapsed: "02:30:00")
      expect(entry.age_human).to eq("2h 30m")
    end

    it "returns days and hours for >=24h" do
      entry = make_entry(elapsed: "3-04:30:00")
      expect(entry.age_human).to eq("3d 4h")
    end
  end

  describe "#total_rss_kb" do
    it "returns own rss_kb when no children" do
      entry = make_entry(rss_kb: 500)
      expect(entry.total_rss_kb).to eq(500)
    end

    it "sums self and children rss_kb" do
      parent = make_entry(pid: 1, rss_kb: 500)
      child = make_entry(pid: 2, ppid: 1, rss_kb: 200)
      parent.children << child
      expect(parent.total_rss_kb).to eq(700)
    end

    it "sums self and nested children recursively" do
      grandparent = make_entry(pid: 1, rss_kb: 100)
      parent = make_entry(pid: 2, ppid: 1, rss_kb: 200)
      child = make_entry(pid: 3, ppid: 2, rss_kb: 300)
      parent.children << child
      grandparent.children << parent
      expect(grandparent.total_rss_kb).to eq(600)
    end
  end

  describe "#leaf?" do
    it "returns true when no children" do
      entry = make_entry
      expect(entry.leaf?).to be true
    end

    it "returns false when children exist" do
      parent = make_entry(pid: 1)
      child = make_entry(pid: 2, ppid: 1)
      parent.children << child
      expect(parent.leaf?).to be false
    end
  end

  describe "#age_seconds" do
    it "parses mm:ss format" do
      entry = make_entry(elapsed: "00:30")
      expect(entry.age_seconds).to eq(30)
    end

    it "parses mm:ss with minutes" do
      entry = make_entry(elapsed: "05:30")
      expect(entry.age_seconds).to eq(330)
    end

    it "parses hh:mm:ss format" do
      entry = make_entry(elapsed: "02:30:00")
      expect(entry.age_seconds).to eq(9000)
    end

    it "parses dd-hh:mm:ss format" do
      entry = make_entry(elapsed: "3-04:30:00")
      expect(entry.age_seconds).to eq(275400)
    end
  end
end
