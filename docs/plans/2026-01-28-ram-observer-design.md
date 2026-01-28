# ram-observer Design

A Ruby terminal UI for macOS that shows a hierarchical tree of processes with detailed memory metrics, freeze/navigate capability, and on-demand AI explanations via Claude Code.

## Key Differentiators from htop

- Tree-first view with parent-child process hierarchy
- Freeze mode - pause the view, navigate freely without display jumping
- AI explain - select any process, get a Claude-powered explanation
- Memory decomposition - RSS, virtual, compressed, swap with inline hints
- Process age - launch time and uptime for each process

## Tech Stack

- Ruby with `curses` gem for TUI
- System data via `ps`, `vm_stat`, `memory_pressure`, `footprint`/`vmmap`
- AI explanations via `claude` CLI

## UI Layout

```
┌─ ram-observer ──────────────────────────────────────────────────┐
│ System: 16GB physical | Used: 11.2G | Swap: 2.1G | Pressure: ██░░ │
├─────────────────────────────────────────────────────────────────┤
│ PID   NAME              RSS    VIRT    COMP   SWAP   AGE       │
│ > 482  iTerm2           1.2G   4.8G   340M   120M   3d 2h     │
│   |- 1205  zsh           28M   410M     4M     0B   3d 2h     │
│   |- 8834  zsh           32M   415M     6M     0B   1h 12m    │
│   |  \- 9012  node      480M   1.2G    80M    40M   45m       │
│   \- 9401  ruby          64M   380M    12M     0B   2m        │
│ > 301  Google Chrome    3.4G   8.2G   890M   450M   2d 5h     │
│ > 119  WindowServer     1.1G   3.2G   200M    30M   5d 11h    │
│   502  Spotlight         890M   2.1G   340M   180M   5d 11h    │
├─────────────────────────────────────────────────────────────────┤
│ [LIVE] Up/Down Navigate  Left/Right Expand  f Freeze  / Search │
│        e Explain  s Sort  x Export  q Quit                     │
│ RSS: Physical memory actively used by this process              │
└─────────────────────────────────────────────────────────────────┘
```

## Keybindings

| Key | Action |
|-----|--------|
| Up/Down | Move selection cursor |
| Left/Right | Collapse/expand tree nodes |
| f | Toggle freeze mode (LIVE/FROZEN) |
| e | AI explain selected process |
| / | Search/filter by process name |
| s | Cycle sort column |
| x | Export snapshot to JSON |
| q | Quit |

## Memory Columns

| Column | Description |
|--------|-------------|
| RSS | Physical memory actively used (resident set size) |
| VIRT | Total virtual address space (includes shared libs, mapped files, reserved) |
| COMP | Memory compressed in RAM by macOS to save space without swapping |
| SWAP | Memory paged out to disk swap file |

## Features

### Tree View
- Processes shown in parent-child hierarchy
- Collapsible nodes with > (collapsed) and v (expanded) indicators
- Children indented with tree lines
- Aggregate memory of children visible on parent row

### Freeze Mode
- Press `f` to freeze - header shows [FROZEN], data stops refreshing
- Navigate freely without the view jumping
- Press `f` again to resume live updates

### AI Explain
- Press `e` on any process
- Opens panel below process list
- Shows full command line and AI-generated explanation
- Sends process name, command args, memory metrics, age, parent chain to `claude` CLI
- Press ESC to close panel

### Search/Filter
- Press `/` to enter search mode
- Type to filter processes by name (case insensitive)
- ESC clears filter and returns to full view
- Matching processes shown with full tree context (parents kept visible)

### Memory Timeline
- Track RSS over time for selected processes since monitoring started
- Show sparkline next to process when data is available

### Process Age
- Show when process was launched
- Display human-readable uptime (e.g., "3d 2h", "45m", "12s")

### Export Snapshot
- Press `x` to export current view to JSON
- Includes all process data, tree structure, system totals
- Saved to `ram-snapshot-YYYY-MM-DD-HHMMSS.json`

## Data Collection

### Process Data
`ps -axo pid,ppid,rss,vsz,comm,etime,lstart` for core metrics.

### Per-Process Memory Detail
`footprint <pid>` or `vmmap -summary <pid>` for compressed and swap breakdown.
These are expensive - only fetched on demand or at low frequency.

### System Totals
- `vm_stat` for page statistics
- `sysctl hw.memsize` for total physical memory
- `memory_pressure` for overall pressure level

## Refresh

- Live mode: refresh every 2 seconds
- Frozen mode: no refresh, holds last snapshot
- Per-process detail (compressed/swap): cached, refreshed every 10 seconds
