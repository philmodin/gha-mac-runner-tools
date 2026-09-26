#!/bin/bash
# Report disk, memory, and cache sizes on a self-hosted macOS runner.
#
# Works both as a runner job hook (ACTIONS_RUNNER_HOOK_JOB_COMPLETED) and as a
# normal workflow step via the composite action in this directory.
# Always exits 0: a failing hook fails the whole job.
#
# Environment overrides:
#   RUNNER_HEALTH_MIN_FREE_GB  warn when free disk drops below this (default 30)
#   RUNNER_HEALTH_WORK_DIR     runner _work dir (default: derived from
#                              RUNNER_WORKSPACE, else ~/actions-runner/_work)

MIN_FREE_GB="${RUNNER_HEALTH_MIN_FREE_GB:-30}"

if [ -n "$RUNNER_HEALTH_WORK_DIR" ]; then
  WORK_DIR="$RUNNER_HEALTH_WORK_DIR"
elif [ -n "$RUNNER_WORKSPACE" ]; then
  WORK_DIR="$(dirname "$RUNNER_WORKSPACE")"
else
  WORK_DIR="$HOME/actions-runner/_work"
fi

FREE_GB=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $4}')
MEM_FREE=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/ {print $2}')
SWAP=$(sysctl -n vm.swapusage 2>/dev/null | awk '{print $6}')
WORK=$(du -sh "$WORK_DIR" 2>/dev/null | cut -f1)
DD=$(du -sh "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | cut -f1)

echo "Runner health: disk ${FREE_GB:-?}GB free | mem ${MEM_FREE:-?} free | swap ${SWAP:-?} | _work ${WORK:-?} | DerivedData ${DD:-?}"

if [ -n "$GITHUB_STEP_SUMMARY" ]; then
  {
    echo "### Runner health"
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| Disk free | ${FREE_GB:-?} GB |"
    echo "| Memory free | ${MEM_FREE:-?} |"
    echo "| Swap used | ${SWAP:-?} |"
    echo "| _work dir | ${WORK:-?} |"
    echo "| DerivedData | ${DD:-?} |"
  } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null
fi

if [[ "$FREE_GB" =~ ^[0-9]+$ ]] && [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
  echo "::warning::Runner low on disk: ${FREE_GB} GB free (threshold ${MIN_FREE_GB} GB)"
fi

exit 0
