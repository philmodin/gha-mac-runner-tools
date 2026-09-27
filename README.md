# gha-mac-runner-tools

Two small tools for self-hosted GitHub Actions runners on macOS: report runner health after jobs, and track how stale the Mac's software is.

- [Runner health](#runner-health): disk, memory, and cache sizes after each job
- [Runner versions](#runner-versions): macOS, Xcode, and dev tool versions vs. the newest releases

Both are plain bash scripts that need only macOS and `curl`. They are read-only and always exit 0, so they never fail a job unless you add a step that does.

## Examples

Health, in the job log after each job:

```
Runner health: disk 195GB free | mem 83% free | swap 0.00M | _work 14G | DerivedData 1.9G
```

Versions, as a run summary table:

> | Tool | Installed | Latest | Behind by | Status |
> |---|---|---|---|---|
> | Xcode | 26.6 | 26.6 |  | ✅ recent · 27 available for 13 days |
> | gh | 2.92.0 | 2.101.0 | 140 days | ⚠️ stale |

## Quick start

Health report at the end of a job:

```yaml
- uses: philmodin/gha-mac-runner-tools/health@main
  if: always()
```

Weekly version report on a runner:

```yaml
on:
  schedule:
    - cron: "17 8 * * 1"
jobs:
  versions:
    runs-on: [self-hosted, macOS]
    steps:
      - uses: philmodin/gha-mac-runner-tools/versions@main
```

`@main` tracks the latest changes. Pin a commit SHA if you want updates only when you choose.

## Runner health

`health/health.sh` prints free disk, free memory, swap used, and the sizes of the runner `_work` dir and Xcode DerivedData. It emits a `::warning::` when free disk drops below a threshold.

### What it reports

> ### Runner health
> | Metric | Value |
> |---|---|
> | Disk free | 195 GB |
> | Memory free | 83% |
> | Swap used | 0.00M |
> | _work dir | 14G |
> | DerivedData | 1.9G |

<details>
<summary>Job log line</summary>

```
Runner health: disk 195GB free | mem 83% free | swap 0.00M | _work 14G | DerivedData 1.9G
```

</details>

### Use as an action (recommended)

```yaml
- uses: philmodin/gha-mac-runner-tools/health@main
  if: always()
  with:
    min-free-gb: 30   # optional, default 30
```

Adds a job log line and a step summary table. No setup on the Mac.

### Install as a job hook

Alternative when you want a report after every job without editing workflows. Output goes to the job log under "Complete runner"; the step summary may not render. Use the hook or the action, not both, or each job reports twice.

1. Copy the script somewhere the runner account owns and make it executable:

   ```sh
   mkdir -p ~/bin
   curl -fsSL https://raw.githubusercontent.com/philmodin/gha-mac-runner-tools/main/health/health.sh -o ~/bin/runner-health.sh
   chmod +x ~/bin/runner-health.sh
   ```

2. Add this line to the `.env` file in the runner's install directory. The path must be absolute:

   ```
   ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/Users/runner/bin/runner-health.sh
   ```

3. Restart the runner (`./svc.sh stop && ./svc.sh start`, or however you launch it).

### Configuration

| Action input | Env var | Default | Purpose |
|---|---|---|---|
| `min-free-gb` | `RUNNER_HEALTH_MIN_FREE_GB` | `30` | Low-disk warning threshold (GB) |
| | `RUNNER_HEALTH_WORK_DIR` | derived from `RUNNER_WORKSPACE`, else `~/actions-runner/_work` | Runner `_work` directory to measure |

For the hook, set env vars in the runner's `.env` file next to the hook line.

## Runner versions

`versions/versions.sh` lists what's installed on the Mac and how far behind the newest release each tool is. It checks macOS, Xcode, Homebrew (and `brew outdated`), claude, tailscale, cloudflared, gh, docker, colima, actions-runner, node, xcodes, swiftlint, swiftformat, tuist, pod, and fastlane. Tools that aren't installed are skipped.

It looks up the newest versions over the network from public endpoints, with no token needed. That makes it a poor fit for a job hook, so run it on a schedule instead.

### What it reports

> ### Runner versions · mac-mini-1
> | Tool | Installed | Latest | Behind by | Status |
> |---|---|---|---|---|
> | macOS | 26.7 | 26.6.2 |  | ✅ recent · 27.0 available for 13 days |
> | Xcode | 26.6 | 26.6 |  | ✅ recent · 27 available for 13 days; /Applications/Xcode.app/Contents/Developer |
> | Homebrew | 7.0.6 | 7.0.6 |  | ✅ current |
> | brew packages | 72 outdated | | | ⚠️ `brew upgrade` |
> | claude | 2.1.250 | 2.1.283 | 29 days | ✅ recent |
> | tailscale | 1.102.4 | 1.102.4 |  | ✅ current |
> | cloudflared | 2026.5.1 | 2026.9.3 | 122 days | ⚠️ stale |
> | gh | 2.92.0 | 2.101.0 | 140 days | ⚠️ stale |
> | docker | 29.8.0 | 29.8.1 | 12 days | ✅ recent |
> | node | 22.23.1 | 22.23.3 | 93 days | ⚠️ stale · newest LTS 24.21.0 |
> | swiftlint | 0.63.3 | 0.65.1 | 86 days | ⚠️ stale |
> | pod | 1.13.0 | 1.17.0 | 1018 days | ❌ outdated |

<details>
<summary>Job log</summary>

With the default `warn: outdated`, each ❌ row also emits a `::warning::` line; `warn: stale` adds the ⚠️ rows.

```
Runner versions:
  macOS          26.7           latest 26.6.2         recent (27.0 available for 13 days)
  Xcode          26.6           latest 26.6           recent (27 available for 13 days; /Applications/Xcode.app/Contents/Developer)
  Homebrew       7.0.6          latest 7.0.6          current
  brew outdated: 72 formulae/casks
  claude         2.1.250        latest 2.1.283        recent 29 days
  tailscale      1.102.4        latest 1.102.4        current
  cloudflared    2026.5.1       latest 2026.9.3       stale 122 days
  gh             2.92.0         latest 2.101.0        stale 140 days
  docker         29.8.0         latest 29.8.1         recent 12 days
  node           22.23.1        latest 22.23.3        stale 93 days (newest LTS 24.21.0)
  swiftlint      0.63.3         latest 0.65.1         stale 86 days
  pod            1.13.0         latest 1.17.0         outdated 1018 days
::warning::pod is outdated: 1.13.0 installed, 1.17.0 available, released 1018 days later
Runner versions: 5 stale (1 outdated)
```

</details>

### Reading the report

- **Status** is based on how many days newer the latest release is than the installed one, falling back to semver when either release date is missing: ✅ current (same version), ✅ recent (≤30 days, or only a patch behind), ⚠️ stale (>30 days, or a minor version behind), ❌ outdated (>180 days, or a major version behind), ❔ unknown (the newest version couldn't be fetched).
- **macOS and Xcode** are compared within their installed major version, since major upgrades are often held back on purpose. A newer major appears as a note (e.g. `27.0 available for 13 days`) and caps the status at ✅ recent, so ✅ current means nothing newer exists. Once its first release listed in Apple's feed is more than 180 days old, the install becomes ⚠️ stale, which lands before the App Store's yearly SDK requirement. If that release date isn't in the feed, it stays recent.
- **Behind by** is the number of days between the installed version's release and the newest release. It's blank if either release date can't be found; Apple's feed only lists recent releases.
- **macOS newer than "Latest"** can happen when Apple's feed hasn't listed the newest update yet. It still counts as current.
- **brew outdated** uses Homebrew's cached metadata and doesn't run `brew update` first.

### Scheduled report across your Macs

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
          warn: outdated   # outdated (default) | stale | none
          skip: ""      # e.g. "node fastlane"
```

Each machine gets its own table in the run summary. To make staleness harder to ignore, add a step that fails when something is outdated:

```yaml
      - if: steps.versions.outputs.outdated != '0'
        run: exit 1
```

### Tracking issue

Set `issue: true` to keep one open issue per runner in the calling repo. When any warning fires, the action finds an open issue titled `mac-runner-kit outdated versions · <runner name>` and replaces its body with the latest table, or creates it. When a later run has no warnings, it closes the issue with a comment. It uses `gh` on the runner and the job's `GITHUB_TOKEN`, so grant the permission:

```yaml
    permissions:
      issues: write
    steps:
      - uses: philmodin/gha-mac-runner-tools/versions@main
        with:
          issue: true
```

To run it by hand on any Mac: `bash versions/versions.sh`.

### Inputs and outputs

| Action input | Env var | Default | Purpose |
|---|---|---|---|
| `warn` | `RUNNER_VERSIONS_WARN` | `outdated` | Emit `::warning::` for `outdated` tools, `stale` or worse, or `none` |
| `skip` | `RUNNER_VERSIONS_SKIP` | empty | Space-separated tool names to skip (see below) |
| `issue` | | `false` | Open, update, or close a tracking issue (see above) |
| `issue-title` | | `mac-runner-kit outdated versions · <runner>` | Issue title to match and create |
| `token` | | `github.token` | Token for the issue; needs `issues: write` |
| | `RUNNER_VERSIONS_RUNNER_DIR` | derived from `RUNNER_WORKSPACE`, else `~/actions-runner` | Actions runner install dir |
| | `RUNNER_VERSIONS_TIMEOUT` | `10` | Per-request timeout in seconds |

Skip names: `macos xcode brew claude tailscale cloudflared gh docker colima runner node xcodes swiftlint swiftformat tuist pod fastlane`.

| Output | Meaning |
|---|---|
| `stale` | Number of tools stale or outdated |
| `outdated` | Number of tools outdated |
| `warned` | Number of `::warning::` lines emitted, which drives the issue |

### Where versions come from

| Tool | Installed version from | Newest version from |
|---|---|---|
| macOS | `sw_vers` | Apple Developer releases feed (newest on your major) |
| Xcode | selected Xcode (`xcode-select -p`) | Apple Developer releases feed (newest on your major) |
| Homebrew | `brew --version` | GitHub `Homebrew/brew`; also counts `brew outdated` |
| claude | `claude --version` | npm `@anthropic-ai/claude-code` |
| tailscale | `tailscale version` (CLI or the app bundle) | GitHub `tailscale/tailscale` |
| cloudflared, gh | `--version` | GitHub releases |
| docker | `docker --version` (the CLI; Docker Desktop bundles one too) | GitHub `moby/moby`, whose release numbers the CLI shares |
| colima | `colima version` | GitHub `abiosoft/colima` |
| actions-runner | `Runner.Listener --version` | GitHub `actions/runner` |
| node | `node --version` | nodejs.org (newest release on your LTS line) |
| xcodes, swiftlint, swiftformat, tuist, pod, fastlane | their version commands | GitHub releases |

Release dates come from the same sources, plus each tag's GitHub release page. They are looked up only for tools that are behind.

## Adding a tool to versions.sh

To track another tool whose releases are on GitHub, add a `task check` line next to the others near the bottom of `versions.sh`, before the `wait`. It runs in parallel with the other checks:

```sh
task check mytool "mytool --version" owner/repo
```
