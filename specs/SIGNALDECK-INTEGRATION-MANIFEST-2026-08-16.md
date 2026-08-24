# SignalDeck integration change manifest

SpatialWorkspace does not currently contain Git metadata. This manifest records the bounded file set changed for the native SignalDeck integration on 2026-08-16. Existing files were read and patched in place. The final SignalDeck binary was launched only for a bounded read-only interoperability check and then stopped.

## Existing files modified

| File | Baseline SHA-256 |
|---|---|
| `README.md` | `1b81e2987a96244f1e25464639be3931b71b8f9a6f9df543e6270a7acfa3a146` |
| `Sources/SpatialWorkspaceApp/SpatialWorkspaceApp.swift` | `595c74fde717144e1c3e16698a1945127f913f678d2d3591c779841eda20c9f1` |
| `Sources/SpatialWorkspaceApp/AppPageNavigation.swift` | `fb90eb0e70febd5eeacc5f8b39dc3e9fcb4e391d2df499b0580a8fe6f26aa1a5` |
| `Sources/SpatialWorkspaceApp/WorkspaceRootView.swift` | `38d3bec3cd06cd56940876261bd68cb3f47e38607a11d7f374eb3f491c575248` |
| `Tests/SpatialWorkspaceTests/StreamingCockpitIntegrationTests.swift` | `c380a61aee22a0d2f0dd8d2a390f6ff376baaee8dc1b0a16334b1fa103c7f588` |

## Files added

- `Sources/SpatialWorkspaceApp/SignalDeckClient.swift`
- `Sources/SpatialWorkspaceApp/SignalDeckController.swift`
- `Sources/SpatialWorkspaceApp/SignalDeckPage.swift`
- `Tests/SpatialWorkspaceTests/SignalDeckIntegrationTests.swift`
- `specs/SIGNALDECK-INTEGRATION-MANIFEST-2026-08-16.md`

## Verification record

- `swift test --filter SignalDeckIntegrationTests`: 9 deterministic tests passed, with the read-only real-service test gated by `RUN_REAL_SIGNALDECK_E2E`.
- `swift test`: 208 tests executed, 10 skipped, 0 failures. This was rerun after adding profile-fingerprint schema validation and the gated live-service test.
- Static scan of the SignalDeck source and focused tests found no placeholders, debug logging, process launch, termination, or stop calls.
- With the final SignalDeck release binary running, `RUN_REAL_SIGNALDECK_E2E=1 swift test --filter SignalDeckIntegrationTests.testRealSignalDeckReadOnlyInteropWhenEnabled` passed. It authenticated through discovery v2, decoded capabilities/snapshot/profiles, verified matching instance and revision evidence, and performed no mutation. The temporary service was then stopped and port 5287 was confirmed closed.

## Final SHA-256

| File | Final SHA-256 |
|---|---|
| `README.md` | `53720974f16454b14c7254db851115f565a994ba148143a75dd27773204f962a` |
| `Sources/SpatialWorkspaceApp/SpatialWorkspaceApp.swift` | `59e852c222ffbe248618bffcdb832404e79e820566944989935d2ea8663278d6` |
| `Sources/SpatialWorkspaceApp/AppPageNavigation.swift` | `6118ff1fcc4ac01f24443a3afa43b3b20d2fab5613251d9fcdffb41305825197` |
| `Sources/SpatialWorkspaceApp/WorkspaceRootView.swift` | `9a282448ea56604d3a1d34a11dfce0d1e77a9ef6380f75fb05681298acc1bb5c` |
| `Sources/SpatialWorkspaceApp/SignalDeckClient.swift` | `88dcbbca424504c841f2fcb684a6c3455151526a46bcae7d0ceae09086bc4f0d` |
| `Sources/SpatialWorkspaceApp/SignalDeckController.swift` | `3896e0c5540e0cce49253ccd96c8996cdfebfe5f2bdd57aca4d4a4e5e7ddfdcb` |
| `Sources/SpatialWorkspaceApp/SignalDeckPage.swift` | `7810bbef894cd177187b4cbb5f57ad7b25148fbf18a3f96c051c54efea46f796` |
| `Tests/SpatialWorkspaceTests/StreamingCockpitIntegrationTests.swift` | `51130a4d9cc46984a4b47203eab6cc192cd0ac69def798190101e4a2bac39fb2` |
| `Tests/SpatialWorkspaceTests/SignalDeckIntegrationTests.swift` | `8151f1cf2d1980c80b33231e4e52c95bbc864b41f3db78effbff1a1a5693d84d` |

The manifest omits its own hash because recording that value would change the file being hashed.
