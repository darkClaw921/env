#!/bin/bash

# Tokyo Night Storm palette
C_RED="\033[38;2;247;118;142m"
C_YELLOW="\033[38;2;224;175;104m"
C_GREEN="\033[38;2;158;206;106m"
C_CYAN="\033[38;2;125;207;255m"
C_BLUE="\033[38;2;122;162;247m"
C_PURPLE="\033[38;2;187;154;247m"
C_GRAY="\033[38;2;86;95;137m"
C_RESET="\033[0m"

# Read JSON input from stdin
input=$(cat)

# Extract current directory - try cwd first, fallback to workspace.current_dir
current_dir=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
if [ -z "$current_dir" ]; then
    current_dir=$(pwd)
fi

# Git information
git_branch=""
git_status=""
if [ -d "$current_dir" ] && git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    # Try symbolic-ref first (works better), then branch --show-current as fallback
    git_branch=$(git -C "$current_dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$git_branch" ]; then
        git_branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
    fi
    if [ -n "$git_branch" ]; then
        if git -C "$current_dir" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null; then
            git_status="✓"
        else
            git_status="✗"
        fi
    fi
fi

# Shorten directory path and split for coloring
short_dir=$(echo "$current_dir" | awk -F'/' '{n = NF; if (n <= 3) print $0; else printf "…/%s/%s/%s", $(n-2), $(n-1), $n}')
# Split into parent path (gray) and current dir (purple)
dir_parent=$(dirname "$short_dir")
dir_name=$(basename "$short_dir")

# Context window usage and available before autocompaction
# Autocompact buffer is 16.5% of context window (33k for 200k model)
context_part=""
usage=$(echo "$input" | jq '.context_window.current_usage')
size=$(echo "$input" | jq '.context_window.context_window_size')

if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
else
    # Zero state - no messages yet
    current=0
fi

# Autocompact triggers at 83.5% (100% - 16.5% buffer)
autocompact_threshold=$((size * 835 / 1000))
# Percentage of usable context (before autocompact)
pct=$((current * 100 / autocompact_threshold))
# Remaining before autocompaction
remaining=$((autocompact_threshold - current))
if [ $remaining -lt 0 ]; then
    remaining=0
    pct=100
fi
# Format remaining tokens (e.g., 110k)
if [ $remaining -ge 1000 ]; then
    remaining_fmt="$((remaining / 1000))k"
else
    remaining_fmt="$remaining"
fi
# Format current tokens
if [ $current -ge 1000 ]; then
    current_fmt="$((current / 1000))k"
else
    current_fmt="$current"
fi
# Dynamic color based on percentage
if [ $pct -gt 80 ]; then
    pct_color="$C_RED"
elif [ $pct -gt 60 ]; then
    pct_color="$C_YELLOW"
else
    pct_color="$C_GREEN"
fi

# Progress bar (10 chars wide)
bar_width=10
filled=$((pct * bar_width / 100))
empty=$((bar_width - filled))
# Clamp values
[ $filled -gt $bar_width ] && filled=$bar_width
[ $filled -lt 0 ] && filled=0
[ $empty -lt 0 ] && empty=0

bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '▓')
bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')
progress_bar="${pct_color}${bar_filled}${C_GRAY}${bar_empty}${C_RESET}"

context_part=$(printf " ${C_GRAY}│${C_RESET} ${pct_color}${pct}%%${C_RESET}: ${current_fmt}${C_GRAY}[${C_RESET}${progress_bar}${C_GRAY}]${C_RESET}${remaining_fmt}")

# Build status line components
dir_part=$(printf "${C_GRAY}${dir_parent}${C_PURPLE}/${dir_name}${C_RESET}")

if [ -n "$git_branch" ]; then
    if [ "$git_status" = "✓" ]; then
        git_part=$(printf " ${C_GRAY}│${C_CYAN} ${git_branch} ${C_GREEN}${git_status}${C_RESET}")
    else
        git_part=$(printf " ${C_GRAY}│${C_CYAN} ${git_branch} ${C_RED}${git_status}${C_RESET}")
    fi
else
    git_part=""
fi

# Session cost and total tokens (including sub-agents)
cost_part=""

# Use cost.total_cost_usd from API (includes sub-agents)
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)

# Sum ALL tokens from transcript (includes sub-agents)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
total_tokens=0

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # Cache token sum keyed by transcript file size (changes with each new message)
    TOKENS_CACHE="$HOME/.cache/claude-tokens-cache"
    transcript_size=$(stat -f '%z' "$transcript_path" 2>/dev/null || echo "0")
    cached_key=""
    cached_val=""
    if [ -f "$TOKENS_CACHE" ]; then
        cached_key=$(head -1 "$TOKENS_CACHE" 2>/dev/null)
        cached_val=$(tail -1 "$TOKENS_CACHE" 2>/dev/null)
    fi
    cache_key="${transcript_path}:${transcript_size}"
    if [ "$cached_key" = "$cache_key" ] && [ -n "$cached_val" ]; then
        total_tokens=$cached_val
    else
        # Sum input+output tokens from all messages in transcript (main + sub-agents)
        total_tokens=$(jq -r '
            (.message.usage // .data.usage // empty) |
            ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) + (.output_tokens // 0))
        ' "$transcript_path" 2>/dev/null | awk '{s+=$1} END {print s+0}')
        # Cache result
        printf '%s\n%s\n' "$cache_key" "$total_tokens" > "$TOKENS_CACHE" 2>/dev/null
    fi
fi

# Format cost
if [ -n "$total_cost" ] && [ "$total_cost" != "0" ]; then
    cost_fmt=$(LC_ALL=C awk "BEGIN {printf \"%.2f\", $total_cost}")
    if [ "$cost_fmt" != "0.00" ]; then
        cost_part=$(printf " ${C_GRAY}│ ~\$${cost_fmt}${C_RESET}")
    fi
fi

# Format total tokens as 1.37M / 456K
if [ "$total_tokens" -gt 0 ]; then
    if [ "$total_tokens" -ge 1000000 ]; then
        tokens_fmt=$(LC_ALL=C awk "BEGIN {printf \"%.2fM\", $total_tokens / 1000000}")
    elif [ "$total_tokens" -ge 1000 ]; then
        tokens_fmt=$(LC_ALL=C awk "BEGIN {printf \"%.0fK\", $total_tokens / 1000}")
    else
        tokens_fmt="${total_tokens}"
    fi
    cost_part=$(printf "%b %b%s%b" "$cost_part" "$C_CYAN" "$tokens_fmt" "$C_RESET")
fi

# ============================================================================
# Rate limits via Anthropic API (5-hour and 7-day limits)
# ============================================================================

CACHE_DIR="$HOME/.cache"
API_CACHE_FILE="$CACHE_DIR/claude-api-response.json"
LOCK_FILE="$CACHE_DIR/claude-usage.lock"

[[ ! -d "$CACHE_DIR" ]] && mkdir -p "$CACHE_DIR"

get_file_age() {
    local file="$1"
    local mod_time=$(stat -f '%m' "$file" 2>/dev/null)
    local now=$(date +%s)
    echo $((now - mod_time))
}

format_remaining_time() {
    local seconds="$1"
    if [[ $seconds -le 0 ]]; then
        echo "0m"
        return
    fi
    local hours=$((seconds / 3600))
    local mins=$(((seconds % 3600) / 60))
    if [[ $hours -gt 0 ]]; then
        echo "${hours}h${mins}m"
    else
        echo "${mins}m"
    fi
}

format_remaining_time_days() {
    local seconds="$1"
    if [[ $seconds -le 0 ]]; then
        echo "0m"
        return
    fi
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local mins=$(((seconds % 3600) / 60))
    if [[ $days -gt 0 ]]; then
        echo "${days}d${hours}h"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h${mins}m"
    else
        echo "${mins}m"
    fi
}

parse_iso_to_seconds_left() {
    local iso_date="$1"
    local clean_date=$(echo "$iso_date" | sed 's/\.[0-9]*//; s/+00:00//; s/Z$//')
    local reset_ts=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$clean_date" "+%s" 2>/dev/null)
    if [[ -n "$reset_ts" ]]; then
        local now=$(date +%s)
        echo $((reset_ts - now))
    else
        echo ""
    fi
}

fetch_api_data() {
    # Use cache if < 60 seconds old
    if [[ -f "$API_CACHE_FILE" ]]; then
        local age=$(get_file_age "$API_CACHE_FILE")
        if [[ $age -lt 60 ]]; then
            cat "$API_CACHE_FILE"
            return 0
        fi
    fi

    # Rate limit: once per 30 seconds
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_age=$(get_file_age "$LOCK_FILE")
        if [[ $lock_age -lt 30 ]]; then
            [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"
            return 0
        fi
    fi
    touch "$LOCK_FILE"

    # Get credentials from Keychain
    local keychain_data=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    [[ -z "$keychain_data" ]] && { [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"; return 0; }

    local token=$(echo "$keychain_data" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [[ -z "$token" ]] && { [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"; return 0; }

    local response=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)

    if [[ -n "$response" ]]; then
        echo "$response" | tee "$API_CACHE_FILE"
    else
        [[ -f "$API_CACHE_FILE" ]] && cat "$API_CACHE_FILE"
    fi
}

make_limit_bar() {
    local pct="$1"
    local color="$2"
    local width=10
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    [[ $filled -gt $width ]] && filled=$width
    [[ $filled -lt 0 ]] && filled=0
    [[ $empty -lt 0 ]] && empty=0
    local bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '▓')
    local bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')
    printf "${C_GRAY}[${C_RESET}${color}${bar_filled}${C_GRAY}${bar_empty}${C_GRAY}]${C_RESET}"
}

# Fetch API data
api_response=$(fetch_api_data 2>/dev/null)

hourly_part=""
weekly_part=""

if [[ -n "$api_response" ]]; then
    # 5-hour limit
    session_pct=$(echo "$api_response" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    if [[ -n "$session_pct" ]]; then
        session_int=${session_pct%.*}
        if [[ $session_int -gt 80 ]]; then
            session_color="$C_RED"
        elif [[ $session_int -gt 60 ]]; then
            session_color="$C_YELLOW"
        else
            session_color="$C_GREEN"
        fi
        session_bar=$(make_limit_bar "$session_int" "$session_color")
        reset_at=$(echo "$api_response" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
        time_fmt="5h"
        if [[ -n "$reset_at" ]]; then
            secs_left=$(parse_iso_to_seconds_left "$reset_at")
            [[ -n "$secs_left" ]] && time_fmt=$(format_remaining_time "$secs_left")
        fi
        hourly_part=$(printf " ${C_GRAY}│${C_RESET} ${C_GRAY}${time_fmt}:${C_RESET} ${session_bar} ${session_color}${session_int}%%${C_RESET}")
    fi

    # 7-day limit
    weekly_pct=$(echo "$api_response" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
    if [[ -n "$weekly_pct" ]]; then
        weekly_int=${weekly_pct%.*}
        if [[ $weekly_int -gt 80 ]]; then
            weekly_color="$C_RED"
        elif [[ $weekly_int -gt 60 ]]; then
            weekly_color="$C_YELLOW"
        else
            weekly_color="$C_GREEN"
        fi
        weekly_bar=$(make_limit_bar "$weekly_int" "$weekly_color")
        reset_at=$(echo "$api_response" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
        time_fmt="7d"
        if [[ -n "$reset_at" ]]; then
            secs_left=$(parse_iso_to_seconds_left "$reset_at")
            [[ -n "$secs_left" ]] && time_fmt=$(format_remaining_time_days "$secs_left")
        fi
        weekly_part=$(printf " ${C_GRAY}│${C_RESET} ${C_GRAY}${time_fmt}:${C_RESET} ${weekly_bar} ${weekly_color}${weekly_int}%%${C_RESET}")
    fi

    # Check for Max subscription (no limits)
    if [[ -z "$session_pct" && -z "$weekly_pct" ]]; then
        hourly_part=$(printf " ${C_GRAY}│ ∞ Max${C_RESET}")
    fi
fi

# Print complete status line
echo -n "${dir_part}${git_part}${context_part}${cost_part}${hourly_part}${weekly_part}"
