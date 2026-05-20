#!/usr/bin/env bash
# Claude Code status line script

input=$(cat)

# --- Data extraction ---
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
session=$(echo "$input" | jq -r '.session_name // ""')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')

# Context window — use pre-calculated percentages
ctx_used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Rate limits (Claude.ai subscription) — matches what /status shows
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# --- Repo name: try git remote, fall back to top-level dir name ---
repo=""
if [ -n "$cwd" ]; then
  remote=$(git -C "$cwd" --no-optional-locks remote get-url origin 2>/dev/null)
  if [ -n "$remote" ]; then
    repo=$(basename "$remote" .git)
  else
    # Walk up to the git root and use that directory name
    git_root=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$git_root" ]; then
      repo=$(basename "$git_root")
    fi
  fi
fi
[ -z "$repo" ] && repo=$(basename "${cwd:-$(pwd)}")

# --- Colors (ANSI) ---
RESET=$'\033[0m'
PURPLE=$'\033[0;35m'
MAGENTA=$'\033[1;35m'
BROWN=$'\033[0;33m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;93m'
DIM=$'\033[2m'
WHITE=$'\033[0;37m'

SEP="${DIM}${WHITE}│${RESET}"

# --- Progress bar helper ---
# Usage: make_bar <percentage> <color> <width>
make_bar() {
  local pct="$1"
  local color="$2"
  local width="${3:-10}"
  if [ -z "$pct" ]; then
    printf "${DIM}[----------]${RESET}"
    return
  fi
  local filled=$(echo "$pct $width" | awk '{v=int($1*$2/100+0.5); if(v<0)v=0; if(v>$2)v=$2; print v}')
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar="${bar}█"; done
  for ((i=0; i<empty; i++)); do bar="${bar}░"; done
  printf "${color}[${bar}]${RESET} ${color}%.0f%%${RESET}" "$pct"
}

# --- Segment: repo (purple) ---
seg_repo="${PURPLE}${repo}${RESET}"

# --- Segment: model (magenta) ---
seg_model="${MAGENTA}${model}${RESET}"

# --- Segment: session (brown) ---
if [ -n "$session" ]; then
  seg_session="${BROWN}${session}${RESET}"
else
  seg_session="${DIM}(no name)${RESET}"
fi

# --- Segment: context window bar (green) ---
seg_ctx=$(make_bar "${ctx_used_pct}" "${GREEN}" 10)
seg_ctx_label="${DIM}ctx${RESET} ${seg_ctx}"

# --- Segment: rate limit bars (yellow for 5h, brown for 7d) ---
# Only shown when rate limit data is available (Claude.ai subscription)
seg_rate=""
if [ -n "$five_hour_pct" ]; then
  seg_5h=$(make_bar "${five_hour_pct}" "${YELLOW}" 10)
  seg_rate="${DIM}5h${RESET} ${seg_5h}"
  if [ -n "$five_hour_resets_at" ]; then
    now=$(date +%s)
    mins_left=$(( (five_hour_resets_at - now + 59) / 60 ))
    [ "$mins_left" -lt 0 ] && mins_left=0
    seg_rate="${seg_rate} ${DIM}(${mins_left}m)${RESET}"
  fi
fi
if [ -n "$seven_day_pct" ]; then
  seg_7d=$(make_bar "${seven_day_pct}" "${BROWN}" 10)
  seg_7d_str="${DIM}7d${RESET} ${seg_7d}"
  if [ -n "$seven_day_resets_at" ]; then
    now=$(date +%s)
    hours_left=$(( (seven_day_resets_at - now + 3599) / 3600 ))
    [ "$hours_left" -lt 0 ] && hours_left=0
    seg_7d_str="${seg_7d_str} ${DIM}(${hours_left}h)${RESET}"
  fi
  if [ -n "$seg_rate" ]; then
    seg_rate="${seg_rate} ${SEP} ${seg_7d_str}"
  else
    seg_rate="${seg_7d_str}"
  fi
fi

# --- Assemble ---
line="${seg_repo} ${SEP} ${seg_model} ${SEP} ${seg_session} ${SEP} ${seg_ctx_label}"
if [ -n "$seg_rate" ]; then
  line="${line} ${SEP} ${seg_rate}"
fi
printf "%s\n" "${line}"
