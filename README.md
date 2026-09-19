<p align="center">

$$
\begin{matrix}
\color{#D2691E}{\text{         ┌─────────┐ ឵឵  ឵឵  ឵឵}}\kern{125pt}\color{#D2691E}{\text{ ឵឵ ឵឵  ឵឵ ┌─────────┐}}\text{} \\
\color{#D2691E}{\text{       ──────│}}\kern{14pt}\color{#ADD8E6}{\text{[▓▓▓▓▓▓▓▓░░░░░]}}\kern{14pt}\color{#D2691E}{\text{│──────}} \\
\color{#D2691E}{\text{ ─────────── │}}\quad\kern{16pt}\color{#5af78e}{\text{𝗧Ξ𝗥𝗠𝗨𝗫}}\kern{10pt}\color{#5af78e}{\text{𝗝Ξ𝗡𝗞}}\kern{16pt}\quad\color{#D2691E}{\text{│ ───────────}} \\
\color{#D2691E}{\text{ ─────────── │}}\kern{14pt}\color{#5af78e}{\text{𝗖}}\kern{10pt}\color{#5af78e}{\text{𝗟}}\kern{10pt}\color{#5af78e}{\text{𝗘}}\kern{10pt}\color{#5af78e}{\text{𝗔}}\kern{10pt}\color{#5af78e}{\text{𝗡}}\kern{10pt}\color{#5af78e}{\text{𝗘}}\kern{10pt}\color{#5af78e}{\text{𝗥}}\kern{14pt}\color{#D2691E}{\text{│ ───────────}} \\
\color{#D2691E}{\text{       ──────│}}\kern{14pt}\color{#ADD8E6}{\text{[░░░░░▓▓▓▓▓▓▓▓]}}\kern{14pt}\color{#D2691E}{\text{│──────}} \\
\color{#D2691E}{\text{         └─────────┘ ឵឵  ឵឵  ឵឵}}\kern{125pt}\color{#D2691E}{\text{ ឵឵  ឵឵  ឵឵└─────────┘}}\text{}
\end{matrix}
$$

</p>
<p align="center">
<a href="https://github.com/DEAD1nsane"><img title="Github" src="https://img.shields.io/badge/Github-DEAD1nsane-ed2043?style=for-the-badge&logo=github"></a>
</p>
<p align="center">
<a href="https://github.com/DEAD1nsane/Termux-Junk-Cleaner-2.0"><img title="Tool" src="https://img.shields.io/badge/Tool-Termux Junk Cleaner-green.svg"></a>
<a href="https://github.com/DEAD1nsane/Termux-Junk-Cleaner-2.0"><img title="Version" src="https://img.shields.io/badge/Version-2.0.1-yellow.svg"></a>
<a href="https://github.com/DEAD1nsane/Termux-Junk-Cleaner-2.0"><img title="Maintainence" src="https://img.shields.io/badge/Maintained%3F-yes-blue.svg"></a>
<a href="https://github.com/ArjunCodesmith"><img title="Original Author" src="https://img.shields.io/badge/Original-ArjunCodesmith-555555.svg"></a>
</p>

## About

Termux Junk Cleaner is a powerful junk cleanup tool designed to optimize and declutter your Termux environment. It offers a clean, interactive interface to remove unnecessary files, logs, cached data, and more.

## Install

Run this one-liner to clone, install dependencies, and make executable:

```bash
# Clone the repository
git clone https://github.com/DEAD1nsane/Termux-Junk-Cleaner-2.0.git

# Navigate to directory
cd Termux-Junk-Cleaner-2.0

# Install fzf (required for interactive menu)
pkg install fzf -y

# Make script executable
chmod +x tjc.sh
```

Then run:
```bash
./tjc.sh
```

Non-interactive options: `--all` (clean everything), `--dry-run` (show reclaimable sizes, delete nothing), `--yes` (skip confirmation), `--help`.

<p align="center">
  <a href="screenshots/dry-run.png">
    <img src="screenshots/dry-run.png" width="80%" />
  </a>
</p>

## Features

- **Interactive Menu** - fzf-powered checkbox interface with arrow key navigation
- **Selective Cleanup** - Choose exactly what to clean
- **Visual Feedback** - Animated loading bars for each operation
- **Cleanup Summary** - View stats after each run

### What it cleans:
| Option | Description |
|--------|-------------|
| Backup files | Removes `*.bak` files |
| Cache files | Clears `~/.cache` and app cache |
| Cached packages | Runs `apt-get clean` |
| Log files | Removes `*.log` files |
| Temporary files | Clears `~/tmp` |
| Unused packages | Runs `apt autoremove` |

## Controls

| Key | Action |
|-----|--------|
| `↑↓` | Navigate |
| `Tab` | Select/Deselect |
| `Ctrl+A` | Select all |
| `Ctrl+D` | Deselect all |
| `Enter` | Start cleanup |
| `Esc` | Quit |

## Screenshots

<p align="center">
  <a href="screenshots/unselected.png">
    <img src="screenshots/unselected.png" width="30%" />
  </a>
  <a href="screenshots/selected.png">
    <img src="screenshots/selected.png" width="30%" />
  </a>
  <a href="screenshots/finished.png">
    <img src="screenshots/finished.png" width="30%" />
  </a>
</p>

## Credits

**ArjunCodesmith** - Original author and creator, logo design

**DEAD1nsane** - Interactive menu UI and loading animations
