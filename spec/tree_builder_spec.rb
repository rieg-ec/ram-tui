require "spec_helper"

RSpec.describe RamObserver::TreeBuilder do
  subject { described_class.new }

  def make_entry(pid:, ppid:, rss: 100)
    RamObserver::ProcessEntry.new(
      pid: pid, ppid: ppid, rss_kb: rss, vsz_kb: rss * 2,
      command: "/usr/bin/proc#{pid}", elapsed: "01:00", started: "Wed Jan 28 17:21:44 2026"
    )
  end

  describe "#build" do
    it "builds parent-child relationships" do
      entries = [
        make_entry(pid: 1, ppid: 0, rss: 500),
        make_entry(pid: 10, ppid: 1, rss: 300),
        make_entry(pid: 20, ppid: 1, rss: 200),
        make_entry(pid: 30, ppid: 10, rss: 100),
      ]

      roots = subject.build(entries)
      expect(roots.length).to eq(1)
      expect(roots[0].pid).to eq(1)
      expect(roots[0].children.length).to eq(2)
      expect(roots[0].children.map(&:pid)).to contain_exactly(10, 20)

      child10 = roots[0].children.find { |c| c.pid == 10 }
      expect(child10.children.length).to eq(1)
      expect(child10.children[0].pid).to eq(30)
    end

    it "sorts roots by total RSS descending" do
      entries = [
        make_entry(pid: 1, ppid: 0, rss: 100),
        make_entry(pid: 2, ppid: 0, rss: 500),
      ]

      roots = subject.build(entries)
      expect(roots.map(&:pid)).to eq([2, 1])
    end
  end

  describe "#flatten" do
    it "flattens only expanded nodes" do
      entries = [
        make_entry(pid: 1, ppid: 0, rss: 500),
        make_entry(pid: 10, ppid: 1, rss: 300),
      ]

      roots = subject.build(entries)
      flat = subject.flatten(roots)
      # Only root visible since not expanded
      expect(flat.length).to eq(1)

      roots[0].expanded = true
      flat = subject.flatten(roots)
      expect(flat.length).to eq(2)
      expect(flat[1][:depth]).to eq(1)
    end
  end
end
