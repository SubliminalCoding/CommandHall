# Durable runtime design

Date: 2026-08-24
Status: implementation contract

## Outcome

Claude Code and Codex work continues when the Spatial Workspace UI exits. Relaunching the UI attaches to the same run, replays unseen output once, and reports completion from direct process evidence. Terminals remain app-owned in this phase because preserving an interactive PTY requires a separate terminal daemon and reconnection protocol.

## Process boundary

The signed app bundle owns a small `spatial-runtime-worker` executable. The UI creates one owner-only run directory per workspace run and launches the worker. The worker creates a new process session, removes its one-use manifest, starts the allowlisted provider executable, sends the goal over stdin, appends combined stdout/stderr to a log, and atomically replaces a status document at lifecycle transitions.

```text
SpatialWorkspace UI
  ├─ one-use 0600 launch manifest
  ├─ spatial-runtime-worker (new process session)
  │    └─ allowlisted claude/codex child
  ├─ append-only output.log
  └─ atomic status.json
```

The UI observes files, not inherited pipes. Closing the UI therefore cannot close the provider's output channel or make it fail with SIGPIPE.

## Durable run directory

Root: `~/Library/Application Support/SpatialWorkspace/runtime/v1/`

Each run directory is named by the existing `WorkspaceRun.id` and contains:

- `launch.json`: one-use manifest, deleted by the worker immediately after decoding;
- `output.log`: append-only provider stream, mode 0600;
- `status.json`: schema version, run/node IDs, harness, worker and child PIDs, state, exit code, timestamps, and bounded error detail;
- `cancel`: an owner-created cancellation request consumed by the worker.

The runtime root and run directories use mode 0700. No API key is written by Spatial Workspace. The child environment is still derived from the current allowlisted environment policy; the launch manifest is transient because it may contain provider session material or bridge credentials.

## Lifecycle

1. The store persists the `WorkspaceRun` as working.
2. The supervisor creates the run directory and launch manifest using that same run ID.
3. The worker calls `setsid`, deletes the manifest, writes `starting`, and launches the provider.
4. Output is appended and fsynced in bounded intervals. The UI tails from its last byte offset.
5. Cancellation creates `cancel`; the worker sends SIGINT, then SIGTERM after the existing grace budget.
6. The worker writes a terminal status only after `waitpid`/`Process` reports the real exit status.
7. The UI converts terminal status into the existing receipt, evidence, artifact, mission, and queued-task paths.

## Relaunch reconciliation

Before marking persisted working runs interrupted, the store asks the durable supervisor for status by `WorkspaceRun.id`:

- `starting` or `running`, live worker PID: restore `activeRunIDs`, replay output, attach observation, and show `Process reattached`;
- terminal status: replay output and finish through the normal receipt path;
- nonterminal status with dead worker: mark interrupted with direct liveness evidence;
- missing or invalid status: preserve the current honest interruption behavior.

PID checks include the recorded process start time where available so a recycled PID cannot be treated as proof of life.

## Safety and operations

- Provider executable paths remain resolved from the existing allowlist; manifests cannot select arbitrary executables.
- Manifest and status decoders reject unknown schema versions and mismatched run/node IDs.
- Logs are bounded by rotation rather than unbounded memory growth.
- Explicit session close, workspace deletion, and Cancel remain kill switches.
- Ordinary app termination never implies cancellation.
- Stale run directories receive age-based cleanup only after terminal evidence is retained in workspace history.

## Acceptance gates

- A diagnostic child remains alive after its launching supervisor process exits.
- A second supervisor attaches, replays output without duplication, and receives the real exit status.
- Cancel works before and after UI reattachment.
- A dead worker with nonterminal status is reported as interrupted, never working.
- Run and node identity mismatches are rejected.
- Launch manifests are removed and owner-only permissions are verified.
- Existing direct-process tests continue to pass for debug diagnostics during migration.
