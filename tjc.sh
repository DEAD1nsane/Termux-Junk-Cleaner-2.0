#!/data/data/com.termux/files/usr/bin/env bash
#
##   Termux-Junk-Cleaner-2.0  :       Junk cleaner
##   Maintainer               :       DEAD1nsane
##   Original author          :       ArjunCodesmith
##   Version                  :       2.1.0
##   Github                   :       https://github.com/DEAD1nsane/Termux-Junk-Cleaner-2.0
#
##    Termux-Junk-Cleaner-2.0  Copyright (C) 2024-2026  ArjunCodesmith (original),
##    DEAD1nsane (maintainer, v2.0 interactive UI and package-cache cleaning)

set -u

author="DEAD1nsane"
original_author="ArjunCodesmith"
version="v2.1.0"

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
declare -i dirs_deleted=0
declare -i links_deleted=0
start_time=$(date +%s)

# Fork additions (v2.1)
FORCE_ENABLED=0

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
    LOADER_PID=$loader_pid

    "$@" > "$out" 2>&1
    local rc=$?
    kill "$loader_pid" 2>/dev/null || true
    wait "$loader_pid" 2>/dev/null || true
    LOADER_PID=""

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
# Safety + lifecycle
# ---------------------------------------------------------------------------

# Refuse to run outside Termux/Android unless --force is given.
ensure_termux() {
    if [ "$(uname -o 2>/dev/null || echo unknown)" = "Android" ] || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]; then
        return 0
    fi
    if [ "$FORCE_ENABLED" -eq 1 ]; then
        log_msg "warn: running outside Termux because --force was given"
        return 0
    fi
    echo -e "${RED}This tool is Termux-only. On other systems paths differ. Re-run with --force to override.${RESET}"
    exit 1
}

LOADER_PID=""
trap 'kill "${LOADER_PID:-}" 2>/dev/null || true' INT TERM EXIT

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
    if ! command -v apt-get &>/dev/null && ! command -v apt &>/dev/null; then
        log_msg "cached packages: apt not installed, skipped"
        echo -e "  ${WHITE}└─ apt not installed — skipped${RESET}"
        return 0
    fi
    if command -v apt-get &>/dev/null; then
        apt-get clean 2>/dev/null
        apt-get autoclean -y 2>/dev/null
    elif command -v apt &>/dev/null; then
        apt clean 2>/dev/null
        apt autoclean -y 2>/dev/null
    fi
    packages_cleaned=$((packages_cleaned + 1))
    log_msg "cached packages: apt cache cleared (+autoclean)"
    echo -e "  ${WHITE}└─ Package cache cleared${RESET}"
}

remove_unused_packages() {
    if ! command -v apt-get &>/dev/null && ! command -v apt &>/dev/null; then
        log_msg "unused packages: apt not installed, skipped"
        echo -e "  ${WHITE}└─ apt not installed — skipped${RESET}"
        return 0
    fi
    # Simulate first: only autoremove when something would actually be removed.
    # The simulation's root/locking NOTE lines are expected noise and are
    # never shown; we parse only the "N to remove" summary line.
    local sim count
    if command -v apt-get &>/dev/null; then
        sim=$(apt-get -s autoremove 2>&1)
    else
        sim=$(apt -s autoremove 2>&1)
    fi
    count=$(printf '%s' "$sim" | grep -oE '[0-9]+ to remove' | grep -oE '^[0-9]+' | head -n 1)
    count=${count:-0}
    if [ "$count" -eq 0 ]; then
        packages_removed=$((packages_removed + 0))
        log_msg "unused packages: nothing to autoremove"
        echo -e "  ${WHITE}└─ No unused packages${RESET}"
        return 0
    fi
    if command -v apt-get &>/dev/null; then
        apt-get autoremove -y >/dev/null 2>&1
    else
        apt autoremove -y >/dev/null 2>&1
    fi
    packages_removed=$((packages_removed + count))
    log_msg "unused packages: autoremove finished, ~${count} removed"
    echo -e "  ${WHITE}└─ Autoremove finished (~${count} packages)${RESET}"
}

clean_temp_files() {
    # -L so a symlinked ~/tmp (-> $PREFIX/tmp) is followed correctly.
    local before after count freed
    before=$(dir_bytes "$HOME_DIR/tmp")
    count=$(find -L "$HOME_DIR/tmp" -type f -delete -print 2>/dev/null | wc -l)
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
# New v2.1 cleaners
# ---------------------------------------------------------------------------

clean_pycache() {
    local b a f count=0 p
    b=$(prune_find "$HOME_DIR" -type f -path '*/__pycache__/*' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    while IFS= read -r p; do
        [ -d "$p" ] && rm -rf "$p" && count=$((count + 1))
    done < <(prune_find "$HOME_DIR" -type d -name '__pycache__' -print 2>/dev/null)
    a=$(prune_find "$HOME_DIR" -type f -path '*/__pycache__/*' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    f=$((b > a ? b - a : 0))
    dirs_deleted=$((dirs_deleted + count))
    bytes_freed=$((bytes_freed + f))
    log_msg "pycache: ${count} __pycache__ dirs, freed $(human "$f")"
    echo -e "  ${WHITE}└─ ${count} __pycache__ directories — freed $(human "$f")${RESET}"
}

clean_cores() {
    local before after count freed
    before=$(prune_find "$HOME_DIR" -type f \( -name 'core' -size +524288 -o -name 'core.*' -o -name '*.core' \) -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    count=$(prune_find "$HOME_DIR" -type f \( -name 'core' -size +524288 -o -name 'core.*' -o -name '*.core' \) -delete -print 2>/dev/null | wc -l)
    after=$(prune_find "$HOME_DIR" -type f \( -name 'core' -size +524288 -o -name 'core.*' -o -name '*.core' \) -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    freed=$((before > after ? before - after : 0))
    files_deleted=$((files_deleted + count))
    bytes_freed=$((bytes_freed + freed))
    log_msg "cores: ${count} crash dumps, freed $(human "$freed")"
    echo -e "  ${WHITE}└─ ${count} core dump files — freed $(human "$freed")${RESET}"
}

clean_broken_links() {
    local count
    count=$(prune_find "$HOME_DIR" -xtype l -delete -print 2>/dev/null | wc -l)
    links_deleted=$((links_deleted + count))
    log_msg "dangling links: ${count}"
    echo -e "  ${WHITE}└─ ${count} dangling symlinks removed${RESET}"
}

clean_empty_dirs() {
    # Depth >= 3 only, pruned trees excluded, so plain $HOME subfolders survive.
    local count
    count=$(find "$HOME_DIR" -mindepth 3 \
        \( -path '*/node_modules' -o -path '*/node_modules/*' \
        -o -path '*/.git' -o -path '*/.git/*' \
        -o -path '*/.cargo' -o -path '*/.cargo/*' \
        -o -path '*/.npm' -o -path '*/.npm/*' \
        -o -path '*/.gradle' -o -path '*/.gradle/*' \
        -o -path '*/go' -o -path '*/go/*' \
        -o -path '*/.local/share/opencode/snapshot' \
        -o -path '*/.local/share/opencode/snapshot/*' \) -prune \
        -o -type d -empty -delete -print 2>/dev/null | wc -l)
    dirs_deleted=$((dirs_deleted + count))
    log_msg "empty dirs: ${count} (depth>=3)"
    echo -e "  ${WHITE}└─ ${count} empty directories removed (depth>=3)${RESET}"
}

clean_go_cache() {
    local msg=""
    if command -v go &>/dev/null; then
        go clean -cache -testcache -fuzzcache 2>/dev/null && msg="go clean"
    fi
    clean_pm_cache "go build cache" "$CACHE_DIR/go-build" "${msg:-true}"
    clean_pm_cache "go mod cache" "$HOME_DIR/go/pkg/mod/.cache" "true"
}

clean_pnpm_cache() {
    if command -v pnpm &>/dev/null; then
        clean_pm_cache "pnpm" "$HOME_DIR/.pnpm-store" "pnpm store prune"
    else
        clean_pm_cache "pnpm" "$HOME_DIR/.pnpm-store" "true"
        [[ -d "$HOME_DIR/.local/share/pnpm/store" ]] && \
            clean_pm_cache "pnpm store" "$HOME_DIR/.local/share/pnpm/store" "true"
    fi
}

clean_yarn_cache() {
    clean_pm_cache "yarn" "$CACHE_DIR/yarn" "true"
    clean_pm_cache "yarn legacy" "$HOME_DIR/.yarn-cache" "true"
}

clean_gradle_cache() {
    clean_pm_cache "gradle" "$HOME_DIR/.gradle/caches" "true"
}

clean_maven_cache() {
    clean_pm_cache "maven" "$HOME_DIR/.m2/repository" "true"
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
        temp)     find -L "$HOME_DIR/tmp" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}' ;;
        npm)      echo $(($(dir_bytes "$HOME_DIR/.npm/_cacache") + $(dir_bytes "$HOME_DIR/.npm/_npx"))) ;;
        bun)      dir_bytes "$HOME_DIR/.bun/install/cache" ;;
        pip)      echo $(($(dir_bytes "$CACHE_DIR/pip") + $(dir_bytes "$CACHE_DIR/uv"))) ;;
        cargo)    echo $(($(dir_bytes "$HOME_DIR/.cargo/registry/src") + $(dir_bytes "$HOME_DIR/.cargo/registry/cache"))) ;;
        pycache)  prune_find "$HOME_DIR" -type f -path '*/__pycache__/*' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}' ;;
        cores)    prune_find "$HOME_DIR" -type f \( -name 'core' -size +524288 -o -name 'core.*' -o -name '*.core' \) -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}' ;;
        brokenlinks) echo 0 ;;  # dangling links have no size; reported by count
        emptydirs)   echo 0 ;;  # empty dirs hold no bytes; reported by count
        go)       echo $(($(dir_bytes "$CACHE_DIR/go-build") + $(dir_bytes "$HOME_DIR/go/pkg/mod/.cache"))) ;;
        pnpm)     echo $(($(dir_bytes "$HOME_DIR/.pnpm-store") + $(dir_bytes "$HOME_DIR/.local/share/pnpm/store"))) ;;
        yarn)     echo $(($(dir_bytes "$CACHE_DIR/yarn") + $(dir_bytes "$HOME_DIR/.yarn-cache"))) ;;
        gradle)   dir_bytes "$HOME_DIR/.gradle/caches" ;;
        maven)    dir_bytes "$HOME_DIR/.m2/repository" ;;
        *)        echo 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

ALL_KEYS=(backup cache aptcache logs temp unused pycache cores brokenlinks emptydirs npm bun pnpm yarn pip go cargo gradle maven)

key_label() {
    case "$1" in
        backup)   echo "Clean backup files" ;;
        cache)    echo "Clean cache files" ;;
        aptcache) echo "Clean cached packages" ;;
        logs)     echo "Clean log files" ;;
        temp)     echo "Clean temporary files" ;;
        unused)   echo "Remove unused packages" ;;
        pycache)  echo "Clean Python bytecode (__pycache__)" ;;
        cores)    echo "Clean core dump files" ;;
        brokenlinks) echo "Remove dangling symlinks" ;;
        emptydirs)   echo "Remove empty directories" ;;
        npm)      echo "Clean npm cache" ;;
        bun)      echo "Clean bun cache" ;;
        pnpm)     echo "Clean pnpm store" ;;
        yarn)     echo "Clean yarn cache" ;;
        pip)      echo "Clean pip/uv cache" ;;
        go)       echo "Clean Go build/mod cache" ;;
        cargo)    echo "Clean cargo cache" ;;
        gradle)   echo "Clean gradle caches" ;;
        maven)    echo "Clean maven repository" ;;
    esac
}

menu_options() {
    # Prints size-annotated options for fzf.
    local k label est
    for k in "${ALL_KEYS[@]}"; do
        label=$(key_label "$k")
        case "$k" in
            aptcache|unused|brokenlinks|emptydirs) printf '%s\n' "$label" ;;
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
        pycache)  run_task "Cleaning Python bytecode" clean_pycache ;;
        cores)    run_task "Cleaning core dumps" clean_cores ;;
        brokenlinks) run_task "Removing dangling symlinks" clean_broken_links ;;
        emptydirs)   run_task "Removing empty directories" clean_empty_dirs ;;
        npm)      run_task "Cleaning npm cache" clean_npm_cache ;;
        bun)      run_task "Cleaning bun cache" clean_bun_cache ;;
        pnpm)     run_task "Cleaning pnpm store" clean_pnpm_cache ;;
        yarn)     run_task "Cleaning yarn cache" clean_yarn_cache ;;
        pip)      run_task "Cleaning pip/uv cache" clean_pip_cache ;;
        go)       run_task "Cleaning Go caches" clean_go_cache ;;
        cargo)    run_task "Cleaning cargo cache" clean_cargo_cache ;;
        gradle)   run_task "Cleaning gradle caches" clean_gradle_cache ;;
        maven)    run_task "Cleaning maven repository" clean_maven_cache ;;
        *)        echo -e "${RED}Unknown category: $1${RESET}" ;;
    esac
}

# Map each full menu line (label + optional size) back to its key.
build_label_map() {
    local k line
    unset LABEL_TO_KEY
    declare -gA LABEL_TO_KEY=()
    for k in "${ALL_KEYS[@]}"; do
        line=$(key_label "$k")
        LABEL_TO_KEY["$line"]="$k"
    done
}

# Dispatch a selected fzf line (or a bare key).
dispatch_label() {
    build_label_map
    local key="${LABEL_TO_KEY[$1]:-}"
    if [ -n "$key" ]; then
        run_key "$key"
    else
        run_key "$1"   # treat as bare key (CLI targets)
    fi
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
    local freed elapsed
    freed=$(human "$bytes_freed")
    elapsed=$(( $(date +%s) - start_time ))
    echo -e "\n${RED}╔══════════════════════════════════════╗${RESET}"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Files deleted:" "$files_deleted"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Dirs removed:" "$dirs_deleted"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Dangling links:" "$links_deleted"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Packages cleaned:" "$packages_cleaned"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Packages removed:" "~$packages_removed"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%10s${WHITE}   ${RED}║${RESET}\n" "Space freed:" "$freed"
    printf "${RED}║${WHITE}  %-22s ${GREEN}%8ss${WHITE}   ${RED}║${RESET}\n" "Time taken:" "$elapsed"
    echo -e "${RED}╚══════════════════════════════════════╝${RESET}"
    log_msg "SUMMARY files=$files_deleted dirs=$dirs_deleted links=$links_deleted cleaned=$packages_cleaned removed=~$packages_removed freed=$freed"
}

show_info() {
    echo -e "\n${WHITE}  Termux disk overview (largest first)${RESET}"
    printf "  ${GREY}%-32s %12s${RESET}\n" "Path" "Size"
    local d name
    local results=""
    for d in "$HOME_DIR"/* "$HOME_DIR"/.[!.]* ; do
        [ -d "$d" ] || continue
        results+="$(dir_bytes "$d")"$'\t'"$d"$'\n'
    done
    for d in "$PREFIX_DIR/var" "$PREFIX_DIR/lib"; do
        if [ -d "$d" ]; then
            results+="$(dir_bytes "$d")"$'\t'"$d"$'\n'
        fi
    done
    printf '%s' "$results" | sort -rn | head -n 15 | while IFS=$'\t' read -r size path; do
        printf "  %-32s %12s\n" "$path" "$(human "$size")"
    done
    echo ""
    df -h "$HOME_DIR" 2>/dev/null | tail -n 1 | awk '{printf "  Disk: used %s of %s (%s used)\n", $3, $2, $5}'
}

show_history() {
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${GREY}  No cleanup history yet.${RESET}"
        return 0
    fi
    echo -e "\n${WHITE}  Recent cleanup runs (last 20):${RESET}"
    grep 'SUMMARY' "$LOG_FILE" 2>/dev/null | tail -n 20
}

usage() {
    cat <<EOF
Termux-Junk-Cleaner $version — maintained fork by $author (orig. $original_author)

Usage: $(basename "$0") [OPTIONS]

  (no args)      Interactive fzf menu (sizes shown per option)
  --all          Run every cleanup (asks for confirmation unless --yes)
  --only k1,k2   Run only these categories (see keys below)
  --exclude e1   Categories to skip when using --all
  --dry-run      Show reclaimable sizes per category, delete nothing
  --info         Analyze disk: biggest dirs + filesystem usage
  --history      Show recent cleanup summaries
  --yes          Skip the confirmation prompt
  --force        Bypass the Termux safety check
  --help         Show this help
  --version      Print version

Category keys: backup cache aptcache logs temp unused pycache cores
               brokenlinks emptydirs npm bun pnpm yarn pip go cargo gradle maven
Legacy flags:  -c cache  -p cached pkgs  -n autoremove  -t temp
               -b backups  -l logs

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --all --yes
  $(basename "$0") -c -t
  $(basename "$0") --only npm,cargo --yes
  $(basename "$0") --all --exclude gradle,maven
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

DRY_RUN=0
RUN_ALL=0
ASSUME_YES=0
SHOW_INFO=0
SHOW_HISTORY=0
TARGET_KEYS=()
EXCLUDE_KEYS=()

# comma-separated key list -> array
keylist_to_array() {
    local spec="$1" dest_ref="$2" item
    local -n dest="$dest_ref"
    if [ -n "$spec" ]; then
        IFS=',' read -ra _items <<< "$spec"
        for item in "${_items[@]}"; do
            item="${item//[[:space:]]/}"
            [ -n "$item" ] && dest+=("$item")
        done
    fi
}

key_allowlisted() {  # key name
    local k="$1"
    case "$k" in
        backup|cache|aptcache|logs|temp|unused|pycache|cores|brokenlinks|emptydirs|npm|bun|pnpm|yarn|pip|go|cargo|gradle|maven) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_key() {  # full fzf line OR bare key -> key (empty when invalid)
    build_label_map
    local key="${LABEL_TO_KEY[$1]:-}"
    if [ -n "$key" ]; then
        printf '%s' "$key"
    elif key_allowlisted "$1"; then
        printf '%s' "$1"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --all) RUN_ALL=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --force) FORCE_ENABLED=1 ;;
        --info) SHOW_INFO=1 ;;
        --history) SHOW_HISTORY=1 ;;
        --only|--exclude)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}$1 needs a comma-separated key list${RESET}"
                usage; exit 1
            fi
            if [ "$1" = "--only" ]; then keylist_to_array "$2" TARGET_KEYS
            else keylist_to_array "$2" EXCLUDE_KEYS; fi
            shift
            ;;
        -[cptbl][cptbl]*)
            # Combined legacy flags, e.g. -ct or -ltb
            src="${1#-}"
            ci=0
            while [ "$ci" -lt "${#src}" ]; do
                ch="${src:$ci:1}"
                case "$ch" in
                    c) TARGET_KEYS+=(cache) ;;
                    p) TARGET_KEYS+=(aptcache) ;;
                    n) TARGET_KEYS+=(unused) ;;
                    t) TARGET_KEYS+=(temp) ;;
                    b) TARGET_KEYS+=(backup) ;;
                    l) TARGET_KEYS+=(logs) ;;
                    *) echo -e "${RED}Unknown flag -$ch in $1${RESET}"; usage; exit 1 ;;
                esac
                ci=$((ci + 1))
            done
            ;;
        -c) TARGET_KEYS+=(cache) ;;
        -p) TARGET_KEYS+=(aptcache) ;;
        -n) TARGET_KEYS+=(unused) ;;
        -t) TARGET_KEYS+=(temp) ;;
        -b) TARGET_KEYS+=(backup) ;;
        -l) TARGET_KEYS+=(logs) ;;
        --help|-h) usage; exit 0 ;;
        --version|--ver|-v) echo "Termux-Junk-Cleaner $version"; exit 0 ;;
        --) shift; break ;;
        *) echo -e "${RED}Unknown option: $1${RESET}"; usage; exit 1 ;;
    esac
    shift
done

ensure_termux

if [ "$SHOW_INFO" -eq 1 ]; then
    show_info
    exit 0
fi

if [ "$SHOW_HISTORY" -eq 1 ]; then
    show_history
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "\n${WHITE}  DRY RUN — reclaimable space per category:${RESET}"
    printf "  ${GREY}%-40s %12s${RESET}\n" "Category" "Size"
    total=0
    for k in "${ALL_KEYS[@]}"; do
        case "$k" in
            aptcache|unused) printf "  %-40s %12s\n" "$(key_label "$k")" "n/a" ;;
            brokenlinks|emptydirs) printf "  %-40s %12s\n" "$(key_label "$k")" "counted" ;;
            *) e=$(estimate "$k"); total=$((total + e)); printf "  %-40s %12s\n" "$(key_label "$k")" "$(human "$e")" ;;
        esac
    done
    printf "  ${GREY}%-40s %12s${RESET}\n" "Estimated total" "$(human "$total")"
    echo -e "${GREY}  (unused-packages count unknown until autoremove runs)${RESET}\n"
    exit 0
fi

# Resolve the work list.
SELECTED=()
for e in "${EXCLUDE_KEYS[@]}"; do
    if ! key_allowlisted "$e"; then
        echo -e "${RED}Unknown --exclude key: $e${RESET}"
        exit 1
    fi
done
if [ "$RUN_ALL" -eq 1 ]; then
    for k in "${ALL_KEYS[@]}"; do
        skip=0
        for e in "${EXCLUDE_KEYS[@]}"; do
            if [ "$e" = "$k" ]; then skip=1; break; fi
        done
        [ "$skip" -eq 0 ] && SELECTED+=("$k")
    done
elif [ "${#TARGET_KEYS[@]}" -gt 0 ]; then
    for k in "${TARGET_KEYS[@]}"; do
        if ! key_allowlisted "$k"; then
            echo -e "${RED}Unknown category key: $k${RESET}"
            exit 1
        fi
        SELECTED+=("$k")
    done
else
    mapfile -t SELECTED < <(fzf_menu)
fi

if [ "${#SELECTED[@]}" -eq 0 ]; then
    exit 0
fi

# Normalize: every choice (fzf line or bare key) becomes a bare key.
RESOLVED_KEYS=()
for choice in "${SELECTED[@]}"; do
    k=$(resolve_key "$choice")
    if [ -z "$k" ]; then
        echo -e "${RED}Unknown selection: $choice${RESET}"
        exit 1
    fi
    RESOLVED_KEYS+=("$k")
done
SELECTED=("${RESOLVED_KEYS[@]}")

if [ "$ASSUME_YES" -ne 1 ]; then
    echo ""
    echo -e "${WHITE}  Selected for cleanup:${RESET}"
    total=0
    for k in "${SELECTED[@]}"; do
        case "$k" in
            aptcache|unused|brokenlinks|emptydirs) printf "  ${GREY}- %s${RESET}\n" "$(key_label "$k")" ;;
            *) e=$(estimate "$k"); total=$((total + e)); printf "  ${GREY}- %-30s %s${RESET}\n" "$(key_label "$k")" "$(human "$e")" ;;
        esac
    done
    printf "  ${GREY}Estimated total: %s${RESET}\n" "$(human "$total")"
    read -r -p $'\e[1;38;2;37;190;106m  Start cleanup? (y/n): \e[0m' confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "\n\e[1;38;2;37;190;106m  Cancelled.\e[0m"
        exit 0
    fi
fi

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
for choice in "${SELECTED[@]}"; do
    run_key "$choice"
done
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

show_summary

# Auto-save the report for non-interactive runs; prompt otherwise.
if [ "$ASSUME_YES" -eq 1 ] || { [ "$RUN_ALL" -ne 1 ] && [ "${#TARGET_KEYS[@]}" -gt 0 ]; }; then
    if save_log; then
        echo -e "${GREY}  Report saved: $LOG_FILE${RESET}"
    fi
else
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
