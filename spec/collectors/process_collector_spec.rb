require "spec_helper"

RSpec.describe RamObserver::Collectors::ProcessCollector do
  subject { described_class.new }

  describe "#parse" do
    it "parses ps output into ProcessEntry objects" do
      output = <<~PS
          PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND
            1     0  14784 435241984   45:25 Wed Jan 28 17:21:44 2026     /sbin/launchd
          362     1  16704 435517696   42:01 Wed Jan 28 17:25:08 2026     /usr/libexec/logd
      PS

      entries = subject.parse(output)
      expect(entries.length).to eq(2)

      launchd = entries[0]
      expect(launchd.pid).to eq(1)
      expect(launchd.ppid).to eq(0)
      expect(launchd.rss_kb).to eq(14784)
      expect(launchd.comm_name).to eq("launchd")
      expect(launchd.command).to eq("/sbin/launchd")
      expect(launchd.started).to eq("Wed Jan 28 17:21:44 2026")
    end

    it "handles commands with spaces and arguments" do
      output = <<~PS
          PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND
          364     1  17248 435381360   42:01 Wed Jan 28 17:25:08 2026     /usr/libexec/UserEventAgent (System)
      PS

      entries = subject.parse(output)
      expect(entries[0].command).to eq("/usr/libexec/UserEventAgent (System)")
    end
  end

  describe "#collect" do
    it "returns entries from the real system" do
      entries = subject.collect
      expect(entries).not_to be_empty
      expect(entries.first).to be_a(RamObserver::ProcessEntry)
    end
  end

  describe "edge cases" do
    it "returns empty array for empty output" do
      entries = subject.parse("")
      expect(entries).to eq([])
    end

    it "returns empty array for header-only output" do
      output = "    PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND\n"
      entries = subject.parse(output)
      expect(entries).to eq([])
    end

    it "skips malformed lines and parses valid ones" do
      output = <<~PS
          PID  PPID    RSS      VSZ ELAPSED STARTED                      COMMAND
        bad line
            1     0  14784 435241984   45:25 Wed Jan 28 17:21:44 2026     /sbin/launchd
        another bad line
      PS

      entries = subject.parse(output)
      expect(entries.length).to eq(1)
      expect(entries[0].pid).to eq(1)
    end
  end
end
