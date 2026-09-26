# runner-tools
Report self hosted runner health on workflows

`health/health.sh` prints free disk, free memory, swap used, and the sizes of the
runner `_work` dir and Xcode DerivedData. It warns (`::warning::`) when free
disk drops below a threshold and always exits 0, so it never fails a job.

It can run two ways, and they work well together.

## Option 1: Runner job hook (every job, no workflow changes)

1. Copy the script somewhere the runner account owns and make it executable:

   ```sh
   mkdir -p ~/bin
   curl -fsSL https://raw.githubusercontent.com/philmodin/runner-tools/main/health/health.sh -o ~/bin/runner-health.sh
   chmod +x ~/bin/runner-health.sh
   ```

   (If this repo is private, copy `health/health.sh` from a local clone instead.)

2. Add this line to the `.env` file in the runner's install directory. The path
   must be absolute:

   ```
   ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/Users/runner/bin/runner-health.sh
   ```

3. Restart the runner (`./svc.sh stop && ./svc.sh start`, or however you launch it).

The output appears in each job's log under the "Complete runner" step. The step
summary table may not render when written from a hook; the log line and warning
still do.

## Option 2: Composite action (summary table in chosen workflows)

```yaml
- uses: philmodin/runner-tools/health@main
  if: always()
  with:
    min-free-gb: 30   # optional, default 30
```

If this repo is private, allow other repos to use it under
Settings → Actions → General → Access.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RUNNER_HEALTH_MIN_FREE_GB` | `30` | Low-disk warning threshold (GB) |
| `RUNNER_HEALTH_WORK_DIR` | derived from `RUNNER_WORKSPACE`, else `~/actions-runner/_work` | Runner `_work` directory to measure |

For the hook, set these in the runner's `.env` file alongside the hook line.
