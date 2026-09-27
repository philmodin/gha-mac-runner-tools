#!/bin/bash
# Report installed versions of macOS, Xcode, and common dev tools on a
# self-hosted Mac, and how stale each one is against the newest release.
#
# Works as a normal workflow step via the composite action in this directory,
# or run by hand / from launchd. Tools that aren't installed are skipped.
# Always exits 0 so it never fails a job; staleness is reported as warnings.
#
# Latest versions come from public, unauthenticated sources:
#   macOS, Xcode   Apple Developer releases RSS
#   claude         npm registry (@anthropic-ai/claude-code)
#   node           nodejs.org release index (newest release on your LTS line)
#   everything else  the GitHub repo's "latest release" redirect
#
# Environment overrides:
#   RUNNER_VERSIONS_WARN        when to emit ::warning:: lines:
#                               major (default) | any | none
#   RUNNER_VERSIONS_SKIP        space-separated tool names to skip, e.g. "node gh"
#   RUNNER_VERSIONS_RUNNER_DIR  actions runner install dir (default: derived
#                               from RUNNER_WORKSPACE, else ~/actions-runner)
#   RUNNER_VERSIONS_TIMEOUT     per-request timeout in seconds (default 10)

WARN_ON="${RUNNER_VERSIONS_WARN:-major}"
SKIP=" ${RUNNER_VERSIONS_SKIP:-} "
TIMEOUT="${RUNNER_VERSIONS_TIMEOUT:-10}"

if [ -n "$RUNNER_VERSIONS_RUNNER_DIR" ]; then
  RUNNER_DIR="$RUNNER_VERSIONS_RUNNER_DIR"
elif [ -n "$RUNNER_WORKSPACE" ]; then
  RUNNER_DIR="$(dirname "$(dirname "$RUNNER_WORKSPACE")")"
else
  RUNNER_DIR="$HOME/actions-runner"
fi

# Runner services and launchd jobs start with a minimal PATH.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

fetch() { curl -fsSL --connect-timeout 5 --max-time "$TIMEOUT" "$@" 2>/dev/null; }

# First dotted version number in the input, without a leading "v".
first_version() { grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }

# Tag of a GitHub repo's latest (non-prerelease) release, via the web redirect,
# which needs no API token and isn't subject to API rate limits.
github_tag() {
  fetch -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
    | sed -n 's|.*/releases/tag/||p'
}

# Release dates (YYYY-MM-DD or "24 Sep 2026") by source; the version is the last arg.
# github_date REPO TAG_PREFIX VERSION, e.g. github_date cli/cli v 2.92.0
github_date() {
  fetch "https://github.com/$1/releases/tag/$2$3" \
    | grep -oE 'datetime="[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 | cut -d'"' -f2
}
# npm_date FILE VERSION — FILE holds the package's full registry document.
npm_date() {
  grep -oE '"[0-9.]+":"[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" | grep -F "\"$2\":" | head -1 | cut -d'"' -f4
}
# node_date FILE VERSION — FILE holds nodejs.org/dist/index.json.
node_date() {
  grep -F "\"version\":\"v$2\"" "$1" | grep -oE '"date":"[0-9-]{10}' | head -1 | cut -d'"' -f4
}
# apple_date NAME VERSION — pubDate of that release in APPLE_RSS, if still listed.
apple_date() {
  printf '%s\n' "$APPLE_RSS" | grep -oE '<title>[^<]*</title>|<pubDate>[^<]*' \
    | grep -A1 -E "^<title>$1 ([A-Za-z]+ )?$2 \(" | grep -oE '[0-9]{1,2} [A-Z][a-z]{2} [0-9]{4}' | head -1
}

epoch() {
  LC_ALL=C date -j -u -f %Y-%m-%d "$1" +%s 2>/dev/null ||
    LC_ALL=C date -j -u -f '%d %b %Y' "$1" +%s 2>/dev/null ||
    LC_ALL=C date -u -d "$1" +%s 2>/dev/null
}

# Whole days from date A to date B; prints nothing if either is missing or B < A.
days_between() {
  local a b
  a=$(epoch "$1") && b=$(epoch "$2") && [ -n "$a" ] && [ -n "$b" ] && ((b >= a)) || return
  echo $(((b - a + 43200) / 86400))
}

# 5 → "5 days", 143 → "143 days (~4 mo)", 450 → "450 days (~1.2 yr)"
fmt_days() {
  local n=$1 t
  if ((n < 60)); then
    echo "$n day$([ "$n" = 1 ] || echo s)"
  elif ((n < 365)); then
    echo "$n days (~$((n / 30)) mo)"
  else
    t=$((n * 10 / 365))
    echo "$n days (~$((t / 10)).$((t % 10)) yr)"
  fi
}

# Compare dotted versions: prints -1, 0, or 1.
ver_cmp() {
  local -a a b
  local i x y
  IFS=. read -ra a <<<"$1"
  IFS=. read -ra b <<<"$2"
  for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
    x=$((10#${a[i]:-0})) y=$((10#${b[i]:-0}))
    if ((x < y)); then echo -1; return; fi
    if ((x > y)); then echo 1; return; fi
  done
  echo 0
}

# Highest version among lines of input.
max_version() {
  local v best=
  while read -r v; do
    [ -z "$v" ] && continue
    if [ -z "$best" ] || [ "$(ver_cmp "$v" "$best")" = 1 ]; then best=$v; fi
  done
  echo "$best"
}

# Final (non-beta, non-RC) releases in Apple's feed, e.g. "macOS 26.6.2 (25G83)"
# or "Xcode 27 (27A266a)". Reads APPLE_RSS, fetched in check_apple.
apple_releases() {
  printf '%s\n' "$APPLE_RSS" \
    | grep -oE "<title>$1 ([A-Za-z]+ )?[0-9]+(\.[0-9]+)* \([0-9A-Za-z]+\)</title>" \
    | sed -E 's/^<title>[^0-9]*([0-9.]+).*/\1/'
}

# Each check runs as a background task writing to $TASK.log/.row/.status;
# results are collected in task order once all finish.
TMP=$(mktemp -d) || exit 0
trap 'rm -rf "$TMP"' EXIT
N=0

task() {
  N=$((N + 1))
  local id
  id=$(printf '%02d' "$N")
  (TASK="$TMP/$id"; "$@") >"$TMP/$id.log" 2>/dev/null &
}

row() { echo "$1" >>"$TASK.row"; }

# report NAME INSTALLED LATEST [NOTE [DATE_CMD...]]
# DATE_CMD, run with a version appended, prints its release date; used only when behind.
report() {
  local name=$1 have=$2 latest=$3 note=$4 status icon days= age=
  shift $(($# < 4 ? $# : 4))
  if [ -z "$have" ]; then
    return
  elif [ -z "$latest" ]; then
    status="unknown"; icon="❔"
  elif [ "$(ver_cmp "$have" "$latest")" -ge 0 ]; then
    status="current"; icon="✅"
  elif [ "${have%%.*}" != "${latest%%.*}" ]; then
    status="major behind"; icon="❌"
  else
    status="behind"; icon="⚠️"
  fi

  if [[ "$status" = *behind ]] && [ $# -gt 0 ]; then
    days=$(days_between "$("$@" "$have")" "$("$@" "$latest")")
    age=${days:+$(fmt_days "$days")}
  fi

  echo "  $(printf '%-14s %-14s latest %-14s %s' "$name" "$have" "${latest:-?}" "$status${age:+ $age}")${note:+ ($note)}"
  row "| $name | $have | ${latest:-?} | $age | $icon $status${note:+ · $note} |"
  echo "$status" >>"$TASK.status"

  if { [ "$status" = "major behind" ] && [ "$WARN_ON" != none ]; } ||
     { [ "$status" = "behind" ] && [ "$WARN_ON" = any ]; }; then
    echo "::warning::$name is $status: $have installed, $latest available${days:+, released $days days later}"
  fi
}

# gh_report NAME INSTALLED GITHUB_REPO [NOTE]
gh_report() {
  local tag latest
  tag=$(github_tag "$3")
  latest=$(first_version <<<"$tag")
  report "$1" "$2" "$latest" "$4" github_date "$3" "${tag%%"$latest"*}"
}

want() { [[ "$SKIP" != *" $1 "* ]]; }
has() { command -v "$1" >/dev/null 2>&1; }

# check NAME COMMAND GITHUB_REPO — for tools whose newest release is on GitHub.
check() {
  want "$1" && has "${2%% *}" || return
  gh_report "$1" "$(eval "$2" 2>/dev/null | first_version)" "$3"
}

# apple_report NAME INSTALLED [NOTE] — compares with the newest release on the
# installed major, since major upgrades are often held back on purpose.
apple_report() {
  local releases newest same note=$3
  releases=$(apple_releases "$1")
  newest=$(max_version <<<"$releases")
  same=$(grep -E "^${2%%.*}(\.|$)" <<<"$releases" | max_version)
  if [ -n "$newest" ] && [ "${newest%%.*}" != "${2%%.*}" ]; then
    note="$newest available${note:+; $note}"
  fi
  report "$1" "$2" "$same" "$note" apple_date "$1"
}

check_apple() {
  want macos || want xcode || return
  APPLE_RSS=$(fetch https://developer.apple.com/news/releases/rss/releases.rss)
  if want macos && has sw_vers; then
    apple_report macOS "$(sw_vers -productVersion)"
  fi
  if want xcode && has xcodebuild; then
    apple_report Xcode "$(xcodebuild -version 2>/dev/null | head -1 | first_version)" "$(xcode-select -p 2>/dev/null)"
  fi
}

check_brew() {
  want brew && has brew || return
  gh_report Homebrew "$(brew --version 2>/dev/null | head -1 | first_version)" Homebrew/brew
  local outdated
  if outdated=$(brew outdated --quiet 2>/dev/null); then
    outdated=$(grep -c . <<<"$outdated")
    echo "  brew outdated: $outdated formulae/casks"
    row "| brew packages | $outdated outdated | | | $([ "$outdated" -eq 0 ] && echo ✅ || echo ⚠️) \`brew upgrade\` |"
  else
    echo "  brew outdated: unknown (command failed)"
    row "| brew packages | ? | | | ❔ unknown |"
  fi
}

check_claude() {
  want claude && has claude || return
  local latest
  fetch https://registry.npmjs.org/@anthropic-ai/claude-code >"$TASK.npm"
  latest=$(grep -oE '"dist-tags":\{[^}]*' "$TASK.npm" | grep -oE '"latest":"[^"]*"' | first_version)
  report claude "$(claude --version 2>/dev/null | first_version)" "$latest" "" npm_date "$TASK.npm"
}

check_tailscale() {
  want tailscale || return
  local ts=tailscale
  has tailscale || ts=/Applications/Tailscale.app/Contents/MacOS/Tailscale
  [ -x "$(command -v "$ts")" ] &&
    gh_report tailscale "$("$ts" version 2>/dev/null | first_version)" tailscale/tailscale
}

check_runner() {
  want runner && [ -x "$RUNNER_DIR/bin/Runner.Listener" ] || return
  gh_report actions-runner "$("$RUNNER_DIR/bin/Runner.Listener" --version 2>/dev/null | first_version)" actions/runner
}

check_node() {
  want node && has node || return
  local have lts newest same_line
  have=$(node --version | first_version)
  fetch https://nodejs.org/dist/index.json >"$TASK.node"
  lts=$(grep '"lts":"' "$TASK.node")
  newest=$(head -1 <<<"$lts" | first_version)
  same_line=$(grep -m1 "\"version\":\"v${have%%.*}\." <<<"$lts" | first_version)
  if [ -n "$same_line" ]; then
    report node "$have" "$same_line" "newest LTS ${newest:-?}" node_date "$TASK.node"
  else
    report node "$have" "$newest" "not an LTS line" node_date "$TASK.node"
  fi
}

task check_apple
task check_brew
task check_claude
task check_tailscale
task check cloudflared "cloudflared --version"   cloudflare/cloudflared
task check gh          "gh --version"            cli/cli
task check_runner
task check_node
task check xcodes      "xcodes version"          XcodesOrg/xcodes
task check swiftlint   "swiftlint version"       realm/SwiftLint
task check swiftformat "swiftformat --version"   nicklockwood/SwiftFormat
task check tuist       "tuist version"           tuist/tuist
task check pod         "pod --version"           CocoaPods/CocoaPods
task check fastlane    "fastlane --version | grep -E '^fastlane [0-9]'" fastlane/fastlane
wait

BEHIND=$(cat "$TMP"/*.status 2>/dev/null | grep -c behind)
MAJOR_BEHIND=$(cat "$TMP"/*.status 2>/dev/null | grep -c 'major behind')

echo "Runner versions:"
cat "$TMP"/*.log 2>/dev/null
echo "Runner versions: $BEHIND behind ($MAJOR_BEHIND major)"

if [ -n "$GITHUB_STEP_SUMMARY" ]; then
  {
    echo "### Runner versions${RUNNER_NAME:+ · $RUNNER_NAME}"
    echo "| Tool | Installed | Latest | Behind by | Status |"
    echo "|---|---|---|---|---|"
    cat "$TMP"/*.row 2>/dev/null
  } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null
fi

if [ -n "$GITHUB_OUTPUT" ]; then
  {
    echo "behind=$BEHIND"
    echo "major-behind=$MAJOR_BEHIND"
  } >> "$GITHUB_OUTPUT" 2>/dev/null
fi

exit 0
