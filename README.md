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

## Example report

Job log:

```
Runner health: disk 195GB free | mem 83% free | swap 0.00M | _work 14G | DerivedData 1.9G
```

Step summary:

> ### Runner health
> | Metric | Value |
> |---|---|
> | Disk free | 195 GB |
> | Memory free | 83% |
> | Swap used | 0.00M |
> | _work dir | 14G |
> | DerivedData | 1.9G |

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
| docker | `docker --version` (the CLI; Docker Desktop bundles one too) | GitHub `moby/moby`, whose release numbers the CLI shares |
| colima | `colima version` | GitHub `abiosoft/colima` |
| actions-runner | `Runner.Listener --version` | GitHub `actions/runner` |
| node | `node --version` | nodejs.org (newest release on your LTS line) |
| xcodes, swiftlint, swiftformat, tuist, pod, fastlane | their version commands | GitHub releases |

Each row is ✅ current, ⚠️ behind (same major), ❌ major behind, or ❔ unknown (the newest version couldn't be fetched). macOS and Xcode are compared within their installed major, since major upgrades are often held back on purpose; a newer major shows as a note and doesn't count toward `major-behind`. When a tool is behind, "Behind by" shows how many days separate the installed version's release from the newest one, e.g. `140 days (~4 mo)`; it's blank if either release date can't be found (Apple's feed only lists recent releases). Release dates come from the same sources, plus the GitHub release page for each tag, and are looked up only for tools that are behind. Output goes to the log, the step summary table, and the `behind` / `major-behind` step outputs. Like the health script, it always exits 0.

Newest versions come from public endpoints with no token needed. The `brew outdated` count uses Homebrew's cached metadata and doesn't run `brew update` first. This makes network calls, so it's a poor fit for a job hook; run it on a schedule instead.

## Example report

Job log (with `warn: any`, each ⚠️ row would also emit a `::warning::` line):

```
Runner versions:
  macOS          26.7           latest 26.6.2         current (27.0 available)
  Xcode          26.6           latest 26.6           current (27 available; /Applications/Xcode.app/Contents/Developer)
  Homebrew       7.0.6          latest 7.0.6          current
  brew outdated: 72 formulae/casks
  claude         2.1.250        latest 2.1.283        behind 29 days
  tailscale      1.102.4        latest 1.102.4        current
  cloudflared    2026.5.1       latest 2026.9.3       behind 122 days (~4 mo)
  gh             2.92.0         latest 2.101.0        behind 140 days (~4 mo)
  docker         29.8.0         latest 29.8.1         behind 12 days
  node           22.23.1        latest 22.23.3        behind 93 days (~3 mo) (newest LTS 24.21.0)
  swiftlint      0.63.3         latest 0.65.1         behind 86 days (~2 mo)
  pod            1.13.0         latest 1.17.0         behind 1018 days (~2.7 yr)
Runner versions: 7 behind (0 major)
```

Step summary:

> ### Runner versions · mac-mini-1
> | Tool | Installed | Latest | Behind by | Status |
> |---|---|---|---|---|
> | macOS | 26.7 | 26.6.2 |  | ✅ current · 27.0 available |
> | Xcode | 26.6 | 26.6 |  | ✅ current · 27 available; /Applications/Xcode.app/Contents/Developer |
> | Homebrew | 7.0.6 | 7.0.6 |  | ✅ current |
> | brew packages | 72 outdated | | | ⚠️ `brew upgrade` |
> | claude | 2.1.250 | 2.1.283 | 29 days | ⚠️ behind |
> | tailscale | 1.102.4 | 1.102.4 |  | ✅ current |
> | cloudflared | 2026.5.1 | 2026.9.3 | 122 days (~4 mo) | ⚠️ behind |
> | gh | 2.92.0 | 2.101.0 | 140 days (~4 mo) | ⚠️ behind |
> | docker | 29.8.0 | 29.8.1 | 12 days | ⚠️ behind |
> | node | 22.23.1 | 22.23.3 | 93 days (~3 mo) | ⚠️ behind · newest LTS 24.21.0 |
> | swiftlint | 0.63.3 | 0.65.1 | 86 days (~2 mo) | ⚠️ behind |
> | pod | 1.13.0 | 1.17.0 | 1018 days (~2.7 yr) | ⚠️ behind |

macOS can show an installed version newer than "Latest" when Apple's feed hasn't listed the newest update yet; that still counts as current.

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
| `RUNNER_VERSIONS_SKIP` | empty | Space-separated tool names to skip (`macos xcode brew claude tailscale cloudflared gh docker colima runner node xcodes swiftlint swiftformat tuist pod fastlane`) |
| `RUNNER_VERSIONS_RUNNER_DIR` | derived from `RUNNER_WORKSPACE`, else `~/actions-runner` | Actions runner install dir |
| `RUNNER_VERSIONS_TIMEOUT` | `10` | Per-request timeout in seconds |

To track another tool whose releases are on GitHub, add a `task check` line with the others near the bottom of `versions.sh` (before the `wait`); it runs in parallel with the other checks:

```sh
task check mytool "mytool --version" owner/repo
```
