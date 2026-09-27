#!/bin/bash
# Open or update one GitHub issue per runner when versions.sh emitted warnings;
# close it once a run is clean. Needs gh and a token with issues: write.
#
# Environment:
#   GH_TOKEN, GITHUB_REPOSITORY   set by the composite action
#   WARNED                        warning count from versions.sh
#   REPORT                        markdown table file from versions.sh
#   ISSUE_TITLE                   default "mac-runner-kit outdated versions · $RUNNER_NAME"

TITLE="${ISSUE_TITLE:-mac-runner-kit outdated versions${RUNNER_NAME:+ · $RUNNER_NAME}}"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

if ! command -v gh >/dev/null 2>&1; then
  echo "::warning::gh not installed; skipping issue"
  exit 0
fi

number=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "\"$TITLE\" in:title" \
  --json number,title --jq ".[] | select(.title == \"$TITLE\") | .number" 2>/dev/null | head -1)
run="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

if [ "${WARNED:-0}" = 0 ]; then
  [ -n "$number" ] &&
    gh issue close "$number" --repo "$GITHUB_REPOSITORY" --comment "All versions within threshold as of [this run]($run)."
  exit 0
fi

body="$TITLE: $WARNED tool(s) past the warning threshold as of [this run]($run), $(date -u +%Y-%m-%d).

$(cat "$REPORT" 2>/dev/null)"

if [ -n "$number" ]; then
  gh issue edit "$number" --repo "$GITHUB_REPOSITORY" --body "$body" >/dev/null && echo "Updated issue #$number"
else
  gh issue create --repo "$GITHUB_REPOSITORY" --title "$TITLE" --body "$body"
fi || echo "::warning::Could not open or update issue; does the job have issues: write?"
exit 0
