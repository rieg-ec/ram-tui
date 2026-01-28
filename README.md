# ram-observer

A terminal UI for macOS that shows a hierarchical tree of processes with detailed memory metrics, freeze/navigate capability, and on-demand AI explanations via Claude.

Unlike Activity Monitor or htop, ram-observer lets you expand parent processes (like iTerm2 or Chrome) to see exactly which child processes are consuming memory, freeze the view to explore without it jumping around, and ask an AI to explain what any process is doing.

## Requirements

- macOS (uses `ps`, `vm_stat`, `footprint`, `memory_pressure`)
- Ruby 3.x
- [Claude CLI](https://github.com/anthropics/claude-code) (for the AI explain feature)

## Setup

```
bundle install
```

## Usage

```
ruby bin/ram-observer
```

## Keybindings

| Key | Action |
|-----|--------|
| `↑`/`↓` or `k`/`j` | Navigate processes |
| `→`/`←` or `l`/`h` | Expand / collapse tree node |
| `f` | Toggle freeze mode (pause live updates) |
| `s` | Cycle sort column (RSS, VIRT, COMP, SWAP, AGE) |
| `/` | Search / filter by process name |
| `e` | AI explain selected process |
| `x` | Export snapshot to JSON |
| `q` | Quit |

## Memory columns

| Column | Meaning |
|--------|---------|
| RSS | Physical memory actively used (Resident Set Size) |
| VIRT | Total virtual address space (includes shared libs, mapped files) |
| COMP | Memory compressed in RAM by macOS |
| SWAP | Memory paged out to disk |
| AGE | Time since process launched |
| SPARK | RSS trend sparkline |

## Running tests

```
bundle exec rspec
```
