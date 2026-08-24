# Completion Matrix

Accepted on 2026-08-15. A visual substitute does not satisfy a runtime requirement.

| Area | Required result | Status | Evidence |
| --- | --- | --- | --- |
| Application | Signed standalone macOS app launches without ClawStudio, npm, or localhost control services | Pass | Release bundle launch plus code-signature and linked-library inspection |
| Projects | Each workspace owns a working folder used by agents, terminals, and previews | Pass | Workspace round-trip and invalid-scope tests |
| Surface | Pan, zoom from 25% to 180%, select, move, resize, focus, minimize without stopping sessions, choose balanced or fill-space layout, and restore without coordinate drift | Pass | Camera, selection, minimize/restore, layout, grouped-move, focus, and relaunch tests |
| Terminal | A node owns a real PTY and interactive shell with authoritative output and exit state | Pass | Real login-zsh integration test |
| Agents | Claude Code and Codex receive goals, stream readable output, cancel, and report actual exit status | Pass | Real-CLI packaged-app checks and supervisor integration tests |
| Proof of work | Accepted tasks persist as runs; completed work shows process evidence and scoped artifacts | Pass | Resolver tests plus real Codex create-artifact receipt test |
| Previews | HTML and local-server artifacts open in linked WebKit nodes from their completion receipts | Pass | Real Codex artifact test, file-URL support, and HTTP WebKit test |
| Composer | Long prompts expand vertically, Shift-Return adds lines, accepted requests clear into visible runs, and routed commands identify their destination | Pass | Shared native composer, dispatch events, run creation, and duplicate-submission tests |
| Sessions | Terminals and agents are named, purpose-scoped, renameable, and repeatable by provider | Pass | Multi-session identity, naming, rename, and provider tests |
| Stage rail | Working, blocked, idle, minimized, mission, and tool nodes remain glanceable in stable status groups; choosing one restores and focuses it | Pass | Stable-order, attention roll-up, minimize/restore, and focus tests |
| Session Guardian | Runtime truth, working-folder and executable diagnostics, conversation identity, ownership limits, interruption recovery, retry/resume, and terminal restart are visible | Pass | Real-process tests, missing-folder checks, interruption reconciliation, draft persistence, and recovery tests |
| Missions | An objective packages independent workers, dependencies, a separate reviewer, one attention surface, cancellation, and human acceptance | Pass | Mission persistence, dependency-gate, delayed-reviewer, failure roll-up, role separation, verification, and duplication tests |
| Review Room | Original request, checks, artifacts, live preview, bounded file or Git detail, acceptance, revision, and reviewer handoff share one workspace-bound surface | Pass | Artifact boundary tests, real WebKit integration, review resolver tests, run verification, and persistent revision draft tests |
| Voice | Microphone produces editable transcription; compound commands are ordered; “go to sleep” cancels listening | Pass | Native Speech implementation, permission descriptions, and policy/routing tests |
| Workspaces | The project switcher exposes folder and activity context; switching restores the complete scene while runtime registries remain alive | Pass | Repeated switching, persistence round-trip, and node-ID tests |
| Browser | WebKit opens, navigates, and refreshes requested URLs | Pass | WebKit integration test against a real local HTTP server |
| Persistence | Atomic state, migration, backup, and visible recovery preserve user work | Pass | Corruption archive, backup recovery, and migration fault-injection tests |
| Safety | Fixed executable adapters, stdin goals, folder validation, cancellation, and stale-node handling prevent accidental spillover | Pass | Negative-path and real-child cancellation tests |
| Accessibility | Controls are labeled and keyboard reachable; animation respects reduced motion | Pass | Packaged accessibility-tree inspection and reduced-motion implementation |
| Performance | Sixty lightweight nodes remain within the manipulation budget on the reference Mac mini | Pass | 60-node/100-move acceptance test, 6 ms observed |

P1 behavior is also present: resumable Claude Code and Codex conversations, bounded terminal scrollback and resizing, editable notes, local media playback, persistent animated background scenes, a live minimized-session shelf, prompt-flight feedback, spoken completion notices, mission-aware workspace duplication as a reusable template, node content focus, and a camera-aware minimap.
