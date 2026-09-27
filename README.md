# gha-mac-runner-tools
Report self hosted runner health on workflows, and keep an eye on how stale the Mac's software is.

- [`health/`](#runner-health): disk, memory, and cache sizes after each job
- [`versions/`](#runner-versions): macOS, Xcode, and dev tool versions vs. the newest releases

# Runner health

`health/health.sh` prints free disk, free memory, swap used, and the sizes of the runner `_work` dir and Xcode DerivedData. It warns (`::warning::`) when free disk drops below a threshold and always exits 0, so it never fails a job.

It can run two ways, and they work well together.

## Option 1: Runner job hook (every job, no workflow changes)

1. Copy the script somewhere the runner account owns and make it executable:

   ```sh
   mkdir -p ~/bin
   curl -fsSL https://raw.githubusercontent.com/philmodin/gha-mac-runner-tools/main/health/health.sh -o ~/bin/runner-health.sh
   chmod +x ~/bin/runner-health.sh
   ```

   (If this repo is private, copy `health/health.sh` from a local clone instead.)

2. Add this line to the `.env` file in the runner's install directory. The path must be absolute:

   ```
   ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/Users/runner/bin/runner-health.sh
   ```

3. Restart the runner (`./svc.sh stop && ./svc.sh start`, or however you launch it).

The output appears in each job's log under the "Complete runner" step. The step summary table may not render when written from a hook; the log line and warning still do.

## Option 2: Composite action (summary table in chosen workflows)

```yaml
- uses: philmodin/gha-mac-runner-tools/health@main
  if: always()
  with:
    min-free-gb: 30   # optional, default 30
```

If this repo is private, allow other repos to use it under Settings → Actions → General → Access.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RUNNER_HEALTH_MIN_FREE_GB` | `30` | Low-disk warning threshold (GB) |
| `RUNNER_HEALTH_WORK_DIR` | derived from `RUNNER_WORKSPACE`, else `~/actions-runner/_work` | Runner `_work` directory to measure |

For the hook, set these in the runner's `.env` file alongside the hook line.

# Runner versions

`versions/versions.sh` lists what's installed on the Mac and how far behind the newest release each tool is. Tools that aren't installed are skipped.

| Tool | Installed version from | Newest version from |
|---|---|---|
| macOS | `sw_vers` | Apple Developer releases feed (newest on your major; a newer major is a note) |
| Xcode | selected Xcode (`xcode-select -p`) | Apple Developer releases feed (newest on your major; a newer major is a note) |
| Homebrew | `brew --version` | GitHub `Homebrew/brew`; also counts `brew outdated` |
| claude | `claude --version` | npm `@anthropic-ai/claude-code` |
| tailscale | `tailscale version` (CLI or the app bundle) | GitHub `tailscale/tailscale` |
| cloudflared, gh | `--version` | GitHub releases |
| actions-runner | `Runner.Listener --version` | GitHub `actions/runner` |
| node | `node --version` | nodejs.org (newest release on your LTS line) |
| xcodes, swiftlint, swiftformat, tuist, pod, fastlane | their version commands | GitHub releases |

Each row is ✅ current, ⚠️ behind (same major), ❌ major behind, or ❔ unknown (the newest version couldn't be fetched). macOS and Xcode are compared within their installed major, since major upgrades are often held back on purpose; a newer major shows as a note and doesn't count toward `major-behind`. Output goes to the log, the step summary table, and the `behind` / `major-behind` step outputs. Like the health script, it always exits 0.

Newest versions come from public endpoints with no token needed. The `brew outdated` count uses Homebrew's cached metadata and doesn't run `brew update` first. This makes network calls, so it's a poor fit for a job hook; run it on a schedule instead.

## Scheduled report across your Macs

```yaml
name: Runner versions
on:
  schedule:
    - cron: "17 8 * * 1"   # Mondays
  workflow_dispatch:

jobs:
  versions:
    strategy:
      fail-fast: false
      matrix:
        runner: [mac-mini-1, mac-mini-2]   # one label per machine
    runs-on: [self-hosted, macOS, "${{ matrix.runner }}"]
    steps:
      - id: versions
        uses: philmodin/gha-mac-runner-tools/versions@main
        with:
          warn: major   # major (default) | any | none
          skip: ""      # e.g. "node fastlane"
```

Each machine gets its own table in the run summary. To make staleness harder to ignore, add a step that fails when something is a major version behind:

```yaml
      - if: steps.versions.outputs.major-behind != '0'
        run: exit 1
```

Run it by hand on any Mac with `bash versions/versions.sh`.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RUNNER_VERSIONS_WARN` | `major` | Emit `::warning::` for `major`, `any` staleness, or `none` |
| `RUNNER_VERSIONS_SKIP` | empty | Space-separated tool names to skip (`macos xcode brew claude tailscale cloudflared gh runner node xcodes swiftlint swiftformat tuist pod fastlane`) |
| `RUNNER_VERSIONS_RUNNER_DIR` | derived from `RUNNER_WORKSPACE`, else `~/actions-runner` | Actions runner install dir |
| `RUNNER_VERSIONS_TIMEOUT` | `10` | Per-request timeout in seconds |

To track another tool whose releases are on GitHub, add a `check` line near the bottom of `versions.sh`:

```sh
check mytool "mytool --version" owner/repo
```
