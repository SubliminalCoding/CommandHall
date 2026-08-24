# Supervision QA Inventory

This inventory maps the four approved supervision features to implementation evidence and acceptance checks. It covers the native macOS app in `build/SpatialWorkspace.app`.

## Stage rail

User flow:

1. Open Stage from the top workspace control.
2. Scan Needs You, Working, Agents & Missions, and Tools without changing the canvas layout.
3. Select a minimized or background session.
4. Confirm that it restores, focuses, and keeps its conversation identity.

Checks:

- Stable ordering follows the saved node order within each status group.
- Mission-owned worker alerts roll up to the mission while it is active.
- Current goal, state, elapsed time, and minimized state are visible without opening a node.
- Stage remains scrollable with more rows than the window can show.

## Mission node

User flow:

1. Open the checkered-flag launcher.
2. Enter a mission name and objective.
3. Choose one or more workers and an optional separate reviewer.
4. Create the drafted mission, then launch it from its node.
5. Open Review Room when the mission reaches its review gate, then accept it.

Checks:

- Worker tasks launch independently and share the mission objective.
- A selected worker cannot also be the reviewer.
- The reviewer remains planned until every worker succeeds.
- A failed, cancelled, missing, or blocked worker changes the mission to Needs You.
- Duplicating a workspace preserves mission structure while replacing every runtime, node, mission, and task identity.

## Review Room

User flow:

1. Finish an agent task that produces a run receipt.
2. Choose Review work.
3. Compare the original request, agent summary, process checks, artifact list, embedded preview, and file or Git detail.
4. Accept, prepare a revision, or send the evidence to another agent.

Checks:

- File detail is limited to the run's workspace and bounded in size.
- Git detail uses the fixed system Git executable and a workspace-contained relative path.
- URLs and supported artifacts render in the native WebKit preview.
- Revision text returns to the original agent and survives an app relaunch.
- A run without proof says that no verifiable artifact was captured.

## Session Guardian

User flow:

1. Click a node's status light or use Open session health from Stage.
2. Inspect runtime state, provider readiness, project folder, executable, conversation identity, and the last run.
3. Use the relevant recovery action.

Checks:

- Missing working folders and missing provider executables are reported before launch.
- Runs left active by an app exit return as interrupted and require attention.
- Resume reuses the stored provider conversation ID; retry uses the prior request.
- Restarting a terminal discards its old PTY and creates a new one when reopened.
- The ownership text states that app-owned child processes and PTYs end when their owning session closes.

## Off-happy-path scenarios

### One worker fails while another succeeds

The mission becomes Needs You, the mission node appears once in Stage, and the successful worker result stays attached for later review. Relaunching the mission retries only planned or blocked work; completed worker tasks are not repeated.

### The app closes during an agent run

On relaunch, the run is marked failed with app-lifecycle evidence, the agent is interrupted, and Stage places it in Needs You. Session Guardian offers retry or resume when a previous request exists. No completion claim is generated.

## Automated coverage

`swift test` executes 104 tests. The routine run passes 101 and skips three gated external-service checks for Codex, the public browser target, and live radio. All three gated checks pass when enabled separately. The same suite passes under Thread Sanitizer. The signed acceptance script also verifies the Developer ID signature, Hardened Runtime, microphone entitlement, native linked libraries, and absence of incomplete implementation markers.
