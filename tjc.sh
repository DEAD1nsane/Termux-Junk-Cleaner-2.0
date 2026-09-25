#!/usr/bin/env bash
#
##   Termux-Junk-Cleaner-2.0  :       Junk cleaner
##   Maintainer               :       DEAD1nsane
##   Original author          :       ArjunCodesmith
##   Version                  :       2.0.1
##   Github                   :       https://github.com/DEAD1nsane/Termux-Junk-Cleaner-2.0
#
##    Termux-Junk-Cleaner-2.0  Copyright (C) 2024-2026  ArjunCodesmith (original),
##    DEAD1nsane (maintainer, v2.0 interactive UI and package-cache cleaning)

set -u

author="DEAD1nsane"
original_author="ArjunCodesmith"
version="v2.0.1"

# Portable base paths (never hardcode /data/data/...).
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
TMP_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
CACHE_DIR="$HOME_DIR/.cache"

LOG_FILE="$HOME_DIR/.cleanup_log.txt"
LOG_BUFFER=""

# Counters for summary
declare -i files_deleted=0
declare -i packages_cleaned=0
declare -i packages_removed=0
declare -i bytes_freed=0

# Colors (rbw-amoled theme)
RED='\e[1;31m'
GREEN='\e[1;32m'
DARK_GREEN='\e[38;2;37;190;106m'
WHITE='\e[1;37m'
GREY='\e[0;37m'
RESET='\e[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# dir_bytes <path> : size in bytes, 0 when missing.
dir_bytes() {
    if [ -d "$1" ]; then
        du -sb "$1" 2>/dev/null | cut -f1
    else
        echo 0
    fi
}

# human <bytes> : pretty size (numfmt when available, fallback otherwise).
human() {
    local b="${1:-0}"
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec --suffix=B "$b" 2>/dev/null || echo "${b}B"
    else
        if [ "$b" -ge 1073741824 ]; then
            awk "BEGIN {printf \"%.1fGB\", $b/1073741824}"
        elif [ "$b" -ge 1048576 ]; then
            awk "BEGIN {printf \"%.1fMB\", $b/1048576}"
        elif [ "$b" -ge 1024 ]; then
            awk "BEGIN {printf \"%.1fKB\", $b/1024}"
        else
            echo "${b}B"
        fi
    fi
}

log_msg() {
    LOG_BUFFER+="[$(date '+%Y-%m-%d %H:%M:%S')] $1"$'\n'
}

save_log() {
    [ -n "$LOG_BUFFER" ] || return 0
    printf '%s' "$LOG_BUFFER" >> "$LOG_FILE" 2>/dev/null
}

animate_loader() {
    local width=30 pos=0 dir=1
    while :; do
        local bar=""
        local i
        for ((i = 0; i < width; i++)); do
            if [ "$i" -eq "$pos" ]; then
                bar="${bar}█"
            else
                bar="${bar}░"
            fi
        done
        echo -ne "\r  ${GREY}[${DARK_GREEN}${bar}${GREY}]${RESET}"
        sleep 0.05
        pos=$((pos + dir))
        if [ "$pos" -ge "$width" ] || [ "$pos" -lt 0 ]; then
            dir=$((-dir))
            pos=$((pos + dir * 2))
        fi
    done
}

# run_task <label> <function> [args...]
run_task() {
    local label="$1"; shift
    local out
    out="$(mktemp "$TMP_DIR/tjc.XXXXXX" 2>/dev/null || mktemp)" || out="/dev/null"

    local width=30
    echo -ne "\n${WHITE}  ▶ ${label}${RESET}\n"
    animate_loader &
    local loader_pid=$!

    "$@" > "$out" 2>&1
    local rc=$?
    kill "$loader_pid" 2>/dev/null || true
    wait "$loader_pid" 2>/dev/null || true

    echo -ne "\r  ${GREY}[${DARK_GREEN}"
    printf '█%.0s' $(seq 1 "$width")
    echo -e "${GREY}]${RESET} done"

    cat "$out"
    [ "$out" != "/dev/null" ] && rm -f "$out"
    return "$rc"
}

# prune_find <base> : find base while skipping heavy/irrelevant trees.
# Usage: prune_find "$HOME" -type f -name '*.bak' ...
prune_find() {
    local base="$1"; shift
    find "$base" \
        \( -path '*/node_modules' -o -path '*/node_modules/*' \
        -o -path '*/.git' -o -path '*/.git/*' \
        -o -path '*/.cargo' -o -path '*/.cargo/*' \
        -o -path '*/.npm' -o -path '*/.npm/*' \
        -o -path '*/.local/share/opencode/snapshot' \
        -o -path '*/.local/share/opencode/snapshot/*' \) -prune \
        -o "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Cleaners (each echoes its own report; run_task wraps them with the loader)
# ---------------------------------------------------------------------------

clean_cache() {
    local before after count1 count2 freed
    before=$(($(dir_bytes "$CACHE_DIR") + $(dir_bytes "$PREFIX_DIR/var/cache")))
    count1=$(find "$CACHE_DIR" -type f -delete -print 2>/dev/null | wc -l)
    count2=$(find "$PREFIX_DIR/var/cache" -type f -delete -print 2>/dev/null | wc -l)
    after=$(($(dir_bytes "$CACHE_DIR") + $(dir_bytes "$PREFIX_DIR/var/cache")))
    freed=$((before > after ? before - after : 0))
    files_deleted=$((files_deleted + count1 + count2))
    bytes_freed=$((bytes_freed + freed))
    log_msg "cache: ${count1} home-cache + ${count2} app-cache files, freed $(human "$freed")"
    echo -e "  ${WHITE}└─ ${count1} cache files, ${count2} app cache files — freed $(human "$freed")${RESET}"
}

clean_cached_packages() {
    if command -v apt-get &>/dev/null; then
        apt-get clean 2>/dev/null
    elif command -v apt &>/dev/null; then
        apt clean 2>/dev/null
    fi
    packages_cleaned=$((packages_cleaned + 1))
    log_msg "cached packages: apt cache cleared"
    echo -e "  ${WHITE}└─ Package cache cleared${RESET}"
}

remove_unused_packages() {
    # Parse the real package count instead of counting output lines.
    local output count
    if command -v apt-get &>/dev/null; then
        output=$(apt-get autoremove -y 2>&1)
    else
        output=$(apt autoremove -y 2>&1)
    fi
    count=$(printf '%s' "$output" | grep -oE '[0-9]+ (packages? will be REMOVED|packages? removed|upgraded, .* newly installed, .* to remove)' | grep -oE '^[0-9]+' | head -n 1)
    if [ -z "${count:-}" ]; then
        if printf '%s' "$output" | grep -qiE '0 (upgraded|to remove)|nothing to do'; then
            count=0
        else
            count=0
        fi
    fi
    packages_removed=$((packages_removed + count))
    log_msg "unused packages: autoremove finished, ~${count} removed"
    echo -e "  ${WHITE}└─ Autoremove finished (~${count} packages)${RESET}"
}

clean_temp_files() {
    local before after count freed
    before=$(dir_bytes "$HOME_DIR/tmp")
    count=$(find "$HOME_DIR/tmp" -type f -delete -print 2>/dev/null | wc -l)
    after=$(dir_bytes "$HOME_DIR/tmp")
    freed=$((before > after ? before - after : 0))
    files_deleted=$((files_deleted + count))
    bytes_freed=$((bytes_freed + freed))
    log_msg "temp: ${count} files, freed $(human "$freed")"
    echo -e "  ${WHITE}└─ ${count} temp files removed — freed $(human "$freed")${RESET}"
}

clean_temp_backup_files() {
    local count
    count=$(prune_find "$HOME_DIR" -type f -name '*.bak' -delete -print 2>/dev/null | wc -l)
    files_deleted=$((files_deleted + count))
    log_msg "backup: ${count} *.bak files"
    echo -e "  ${WHITE}└─ ${count} backup files removed${RESET}"
}

clean_unnecessary_logs() {
    # Scoped on purpose: only caches, tmp, Termux-internal logs and
    # top-level $HOME logs. Never recurses into app data dirs (e.g.
    # ~/.local/share/opencode/log) where logs may actually matter.
    local count=0 n
    for d in "$CACHE_DIR" "$TMP_DIR" "$PREFIX_DIR/var/log" "$HOME_DIR/tmp"; do
        [ -d "$d" ] || continue
        n=$(find "$d" -type f -name '*.log' -delete -print 2>/dev/null | wc -l)
        count=$((count + n))
    done
    n=$(find "$HOME_DIR" -maxdepth 1 -type f -name '*.log' -delete -print 2>/dev/null | wc -l)
    count=$((count + n))
    files_deleted=$((files_deleted + count))
    log_msg "logs: ${count} scoped *.log files (cache/tmp/top-level only)"
    echo -e "  ${WHITE}└─ ${count} log files removed (scoped: cache/tmp/top-level)${RESET}"
}

# Generic package-manager cache cleaner.
clean_pm_cache() {
    local name="$1" dir="$2" clean_cmd="$3"
    local before after freed
    before=$(dir_bytes "$dir")
    if [ "$before" -le 0 ]; then
        echo -e "  ${WHITE}└─ ${name}: nothing cached${RESET}"
        return 0
    fi
    # shellcheck disable=SC2086
    eval "$clean_cmd" >/dev/null 2>&1 || rm -rf "${dir:?}/"* 2>/dev/null
    after=$(dir_bytes "$dir")
    freed=$((before > after ? before - after : 0))
    bytes_freed=$((bytes_freed + freed))
    log_msg "${name} cache: freed $(human "$freed")"
    echo -e "  ${WHITE}└─ ${name}: freed $(human "$freed")${RESET}"
}

clean_npm_cache() {
    if command -v npm &>/dev/null; then
        clean_pm_cache "npm" "$HOME_DIR/.npm/_cacache" "npm cache clean --force"
    else
        clean_pm_cache "npm" "$HOME_DIR/.npm/_cacache" "rm -rf $HOME_DIR/.npm/_cacache/*"
    fi
    # npx cache rides along
    if [ -d "$HOME_DIR/.npm/_npx" ]; then
        local b a f
        b=$(dir_bytes "$HOME_DIR/.npm/_npx")
        rm -rf "$HOME_DIR/.npm/_npx" 2>/dev/null
        a=$(dir_bytes "$HOME_DIR/.npm/_npx")
        f=$((b > a ? b - a : 0))
        bytes_freed=$((bytes_freed + f))
        log_msg "npx cache: freed $(human "$f")"
        echo -e "  ${WHITE}└─ npx: freed $(human "$f")${RESET}"
    fi
}

clean_bun_cache() {
    clean_pm_cache "bun" "$HOME_DIR/.bun/install/cache" "bun pm cache rm"
}

clean_pip_cache() {
    if command -v pip &>/dev/null; then
        clean_pm_cache "pip" "$CACHE_DIR/pip" "pip cache purge"
    else
        echo -e "  ${WHITE}└─ pip: not installed${RESET}"
    fi
    if command -v uv &>/dev/null; then
        clean_pm_cache "uv" "$CACHE_DIR/uv" "uv cache clean"
    elif [ -d "$CACHE_DIR/uv" ]; then
        clean_pm_cache "uv" "$CACHE_DIR/uv" "rm -rf $CACHE_DIR/uv/*"
    fi
}

clean_cargo_cache() {
    # Keep the registry index (re-download is slow); drop src + .crate files.
    local b a f
    b=$(($(dir_bytes "$HOME_DIR/.cargo/registry/src") + $(dir_bytes "$HOME_DIR/.cargo/registry/cache")))
    if [ "$b" -le 0 ]; then
        echo -e "  ${WHITE}└─ cargo: nothing cached${RESET}"
        return 0
    fi
    rm -rf "$HOME_DIR/.cargo/registry/src" "$HOME_DIR/.cargo/registry/cache" 2>/dev/null
    a=$(($(dir_bytes "$HOME_DIR/.cargo/registry/src") + $(dir_bytes "$HOME_DIR/.cargo/registry/cache")))
    f=$((b > a ? b - a : 0))
    bytes_freed=$((bytes_freed + f))
    log_msg "cargo cache: freed $(human "$f")"
    echo -e "  ${WHITE}└─ cargo: freed $(human "$f") (index kept)${RESET}"
}

# ---------------------------------------------------------------------------
# Estimates (for menu annotations + --dry-run)
# ---------------------------------------------------------------------------

estimate() {
    # Echoes bytes reclaimable for a given option key.
    case "$1" in
        backup)   prune_find "$HOME_DIR" -type f -name '*.bak' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}' ;;
        cache)    echo $(($(dir_bytes "$CACHE_DIR") + $(dir_bytes "$PREFIX_DIR/var/cache"))) ;;
        aptcache) echo 0 ;;  # apt cache size varies; report as unknown
        logs)     { for d in "$CACHE_DIR" "$TMP_DIR" "$PREFIX_DIR/var/log" "$HOME_DIR/tmp"; do [ -d "$d" ] && find "$d" -type f -name '*.log' -printf '%s\n' 2>/dev/null; done; find "$HOME_DIR" -maxdepth 1 -type f -name '*.log' -printf '%s\n' 2>/dev/null; } | awk '{s+=$1} END {print s+0}' ;;
        temp)     dir_bytes "$HOME_DIR/tmp" ;;
        npm)      echo $(($(dir_bytes "$HOME_DIR/.npm/_cacache") + $(dir_bytes "$HOME_DIR/.npm/_npx"))) ;;
        bun)      dir_bytes "$HOME_DIR/.bun/install/cache" ;;
        pip)      echo $(($(dir_bytes "$CACHE_DIR/pip") + $(dir_bytes "$CACHE_DIR/uv"))) ;;
        cargo)    echo $(($(dir_bytes "$HOME_DIR/.cargo/registry/src") + $(dir_bytes "$HOME_DIR/.cargo/registry/cache"))) ;;
        *)        echo 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

ALL_KEYS=(backup cache aptcache logs temp unused npm bun pip cargo)

key_label() {
    case "$1" in
        backup)   echo "Clean backup files" ;;
        cache)    echo "Clean cache files" ;;
        aptcache) echo "Clean cached packages" ;;
        logs)     echo "Clean log files" ;;
        temp)     echo "Clean temporary files" ;;
        unused)   echo "Remove unused packages" ;;
        npm)      echo "Clean npm cache" ;;
        bun)      echo "Clean bun cache" ;;
        pip)      echo "Clean pip/uv cache" ;;
        cargo)    echo "Clean cargo cache" ;;
    esac
}

menu_options() {
    # Prints size-annotated options for fzf.
    local k label est
    for k in "${ALL_KEYS[@]}"; do
        label=$(key_label "$k")
        case "$k" in
            aptcache|unused) printf '%s\n' "$label" ;;
            *) est=$(estimate "$k"); printf '%s (%s)\n' "$label" "$(human "$est")" ;;
        esac
    done
}

run_key() {
    case "$1" in
        backup)   run_task "Cleaning backup files" clean_temp_backup_files ;;
        cache)    run_task "Cleaning cache files" clean_cache ;;
        aptcache) run_task "Cleaning cached packages" clean_cached_packages ;;
        logs)     run_task "Cleaning log files" clean_unnecessary_logs ;;
        temp)     run_task "Cleaning temporary files" clean_temp_files ;;
        unused)   run_task "Removing unused packages" remove_unused_packages ;;
        npm)      run_task "Cleaning npm cache" clean_npm_cache ;;
        bun)      run_task "Cleaning bun cache" clean_bun_cache ;;
        pip)      run_task "Cleaning pip/uv cache" clean_pip_cache ;;
        cargo)    run_task "Cleaning cargo cache" clean_cargo_cache ;;
    esac
}

# Strip the " (size)" suffix back to the bare label, then dispatch.
dispatch_label() {
    local label="${1%% (*}"
    case "$label" in
        "Clean backup files") run_key backup ;;
        "Clean cache files") run_key cache ;;
        "Clean cached packages") run_key aptcache ;;
        "Clean log files") run_key logs ;;
        "Clean temporary files") run_key temp ;;
        "Remove unused packages") run_key unused ;;
        "Clean npm cache") run_key npm ;;
        "Clean bun cache") run_key bun ;;
        "Clean pip/uv cache") run_key pip ;;
        "Clean cargo cache") run_key cargo ;;
    esac
}

fzf_menu() {
    if ! command -v fzf &>/dev/null; then
        echo -e "${RED}fzf is not installed. Install with: pkg install fzf${RESET}"
        exit 1
    fi

    local selected
    selected=$(menu_options | fzf \
        --multi \
        --cycle \
        --no-input \
        --header="            ┌─────────┐     ┌─────────┐
          ──────│ [▓▓▓▓▓▓▓▓░░░░░] │──────
    ─────────── │   TΞRMUX JΞNK   │ ───────────
    ─────────── │  C L E A N E R  │ ───────────
          ──────│ [░░░░░▓▓▓▓▓▓▓▓] │──────
            └─────────┘     └─────────┘" \
        --footer="       ↑↓:navigate | tab:select | esc:quit
       ctrl-a:all | ctrl-d:none | enter:start " \
        --height=50% \
        --reverse \
        --border=rounded \
        --margin=1,2 \
        --color=border:#ffffff,header:#25BE6A,info:white,pointer:#25BE6A,marker:#5FAFFF,footer:#25BE6A \
        --bind="ctrl-a:select-all" \
        --bind="ctrl-d:deselect-all")

    if [ -z "$selected" ]; then
        echo -e "\n\e[1;38;2;37;190;106m  No options selected. Run again and use Tab to select.\e[0m"
        exit 0
    fi
    printf '%s\n' "$selected"
}

# ---------------------------------------------------------------------------
# Summary (width-safe via printf)
# ---------------------------------------------------------------------------

show_summary() {
    local freed
    freed=$(human "$bytes_freed")
    echo -e "\n${RED}╔══════════════════════════════════════╗${RESET}"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Files deleted:" "$files_deleted"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Packages cleaned:" "$packages_cleaned"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Packages removed:" "~$packages_removed"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Space freed:" "$freed"
    echo -e "${RED}╚══════════════════════════════════════╝${RESET}"
    log_msg "SUMMARY files=$files_deleted cleaned=$packages_cleaned removed=~$packages_removed freed=$freed"
}

usage() {
    cat <<EOF
Termux-Junk-Cleaner $version — maintained fork by $author (orig. $original_author)

Usage: $(basename "$0") [OPTIONS]

  (no args)      Interactive fzf menu (sizes shown per option)
  --all          Run every cleanup (asks for confirmation unless --yes)
  --dry-run      Show reclaimable sizes per category, delete nothing
  --yes          Skip the confirmation prompt
  --help         Show this help

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --all --yes
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

DRY_RUN=0
RUN_ALL=0
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --all) RUN_ALL=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo -e "${RED}Unknown option: $arg${RESET}"; usage; exit 1 ;;
    esac
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "\n${WHITE}  DRY RUN — reclaimable space per category:${RESET}"
    printf "  ${GREY}%-24s %12s${RESET}\n" "Category" "Size"
    total=0
    for k in "${ALL_KEYS[@]}"; do
        case "$k" in
            aptcache|unused) printf "  %-24s %12s\n" "$(key_label "$k")" "n/a" ;;
            *) e=$(estimate "$k"); total=$((total + e)); printf "  %-24s %12s\n" "$(key_label "$k")" "$(human "$e")" ;;
        esac
    done
    printf "  ${GREY}%-24s %12s${RESET}\n" "Estimated total" "$(human "$total")"
    echo -e "${GREY}  (unused-packages count unknown until autoremove runs)${RESET}\n"
    exit 0
fi

# Resolve the work list.
SELECTED=()
if [ "$RUN_ALL" -eq 1 ]; then
    for k in "${ALL_KEYS[@]}"; do
        SELECTED+=("$(key_label "$k")")
    done
else
    mapfile -t SELECTED < <(fzf_menu)
fi

if [ "${#SELECTED[@]}" -eq 0 ]; then
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    echo ""
    read -r -p $'\e[1;38;2;37;190;106m  Start cleanup? (y/n): \e[0m' confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "\n\e[1;38;2;37;190;106m  Cancelled.\e[0m"
        exit 0
    fi
fi

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
for choice in "${SELECTED[@]}"; do
    dispatch_label "$choice"
done
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

show_summary

if [ "$ASSUME_YES" -ne 1 ]; then
    echo ""
    read -r -p $'\e[1;38;2;37;190;106m  Save cleanup report? (y/n): \e[0m' save_report
    if [[ "$save_report" == "y" || "$save_report" == "Y" ]]; then
        if save_log; then
            echo -e "${GREEN}  Report saved: $LOG_FILE${RESET}"
        else
            echo -e "${RED}  Could not save cleanup report.${RESET}"
        fi
    else
        echo -e "${GREY}  No cleanup report saved.${RESET}"
    fi
fi
