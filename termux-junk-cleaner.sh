#!/data/data/com.termux/files/usr/bin/bash

##   Termux-Junk-Cleaner    :       Junk cleaner
##   Author                 :       ArjunCodesmith
##   Version                :       0.3.0
##   Github                 :       https://github.com/ArjunCodesmith

##    Termux-Junk-Cleaner  Copyright (C) 2024  ArjunCodesmith (https://github.com/ArjunCodesmith)

author="ArjunCodesmith"
version="v0.3.0"

LOG_FILE="$HOME/.cleanup_log.txt"

# Counters for summary
declare -i files_deleted=0
declare -i packages_cleaned=0
declare -i packages_removed=0

# Colors (rbw-amoled theme)
RED='\e[1;31m'
GREEN='\e[1;32m'
DARK_GREEN='\e[38;2;37;190;106m'
WHITE='\e[1;37m'
GREY='\e[0;37m'
RESET='\e[0m'

# Loading bar animation
loading_bar() {
    local label="$1"
    local width=30
    local filled=0

    echo -ne "\n${WHITE}  ▶ ${label}${RESET}\n"
    echo -ne "${GREY}  ["

    while [ $filled -le $width ]; do
        local bar=""
        for ((i=0; i<filled; i++)); do
            bar="${bar}█"
        done
        for ((i=filled; i<width; i++)); do
            bar="${bar}░"
        done
        echo -ne "\r  ${GREY}[${DARK_GREEN}${bar}${GREY}]${RESET}"
        sleep 0.02
        filled=$((filled + 1))
    done

    echo -e ""
}

# Function to clean cache files
clean_cache() {
    loading_bar "Cleaning cache files"
    local count1=$(find /data/data/com.termux/files/home/.cache/ -type f -delete -print 2>/dev/null | wc -l)
    local count2=$(find /data/data/com.termux/cache -type f -delete -print 2>/dev/null | wc -l)
    files_deleted=$((files_deleted + count1 + count2))
    echo -e "  ${WHITE}└─ ${count1} cache files${RESET}"
    echo -e "  ${WHITE}└─ ${count2} app cache files${RESET}"
}

# Function to clean cached packages
clean_cached_packages() {
    loading_bar "Cleaning cached packages"
    apt-get clean 2>/dev/null
    packages_cleaned=$((packages_cleaned + 1))
    echo -e "  ${WHITE}└─ Package cache cleared${RESET}"
}

# Function to remove unnecessary or unused packages
remove_unused_packages() {
    loading_bar "Removing unused packages"
    local output=$(apt autoremove -y 2>/dev/null)
    local count=$(echo "$output" | grep -c "removed\|Removed" 2>/dev/null || echo 0)
    count=$(echo "$count" | tr -d '[:space:]')
    packages_removed=$((packages_removed + count))
    echo -e "  ${WHITE}└─ ${count} packages removed${RESET}"
}

# Function to clean temporary files
clean_temp_files() {
    loading_bar "Cleaning temporary files"
    local count=$(find /data/data/com.termux/files/home/tmp/ -type f -delete -print 2>/dev/null | wc -l)
    files_deleted=$((files_deleted + count))
    echo -e "  ${WHITE}└─ ${count} temp files removed${RESET}"
}

# Function to clean temporary backup files
clean_temp_backup_files() {
    loading_bar "Cleaning backup files"
    local count=$(find /data/data/com.termux/files/home/ -type f -name "*.bak" -delete -print 2>/dev/null | wc -l)
    files_deleted=$((files_deleted + count))
    echo -e "  ${WHITE}└─ ${count} backup files removed${RESET}"
}

# Function to clean unnecessary logs
clean_unnecessary_logs() {
    loading_bar "Cleaning log files"
    local count=$(find /data/data/com.termux/files/home -type f -name "*.log" -delete -print 2>/dev/null | wc -l)
    files_deleted=$((files_deleted + count))
    echo -e "  ${WHITE}└─ ${count} log files removed${RESET}"
}

# Interactive fzf menu
fzf_menu() {
    if ! command -v fzf &>/dev/null; then
        echo -e "${RED}fzf is not installed. Install with: pkg install fzf${RESET}"
        exit 1
    fi

    local options=(
        "Clean backup files"
        "Clean cache files"
        "Clean cached packages"
        "Clean log files"
        "Clean temporary files"
        "Remove unused packages"
    )

    local selected
    selected=$(printf '%s\n' "${options[@]}" | fzf \
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

    # Confirm before running
    echo ""
    read -p $'\e[1;38;2;37;190;106m  Start cleanup? (y/n): \e[0m' confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "\n\e[1;38;2;37;190;106m  Cancelled.\e[0m"
        exit 0
    fi

    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    # Run selected cleanups
    while IFS= read -r choice; do
        case "$choice" in
            "Clean backup files") clean_temp_backup_files ;;
            "Clean cache files") clean_cache ;;
            "Clean cached packages") clean_cached_packages ;;
            "Clean log files") clean_unnecessary_logs ;;
            "Clean temporary files") clean_temp_files ;;
            "Remove unused packages") remove_unused_packages ;;
        esac
    done <<< "$selected"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# Show cleanup summary
show_summary() {
    echo -e "\n${RED}╔════════════════════════════════════╗${RESET}"
    echo -e "${RED}║${WHITE}         CLEANUP SUMMARY            ${RED}║${RESET}"
    echo -e "${RED}╠════════════════════════════════════╣${RESET}"
    echo -e "${RED}║${WHITE}  Files deleted:    ${GREEN}$files_deleted${WHITE}             ${RED}║${RESET}"
    echo -e "${RED}║${WHITE}  Packages cleaned: ${GREEN}$packages_cleaned${WHITE}             ${RED}║${RESET}"
    echo -e "${RED}║${WHITE}  Packages removed: ${GREEN}$packages_removed${WHITE}             ${RED}║${RESET}"
    echo -e "${RED}╚════════════════════════════════════╝${RESET}"
    echo -e "${GREEN}  Cleanup completed!${RESET}\n"
}

# Interactive mode
interactive_mode() {
    fzf_menu

    # Ask about log summary
    echo ""
    read -p $'\e[1;37m  Show cleanup log? (y/n): \e[0m' show_log
    if [[ "$show_log" == "y" || "$show_log" == "Y" ]]; then
        show_summary
    else
        echo -e "\n${GREEN}  Cleanup completed!${RESET}"
    fi
}

# Main execution
interactive_mode
