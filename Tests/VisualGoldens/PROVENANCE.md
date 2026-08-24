# Visual golden provenance

These reviewed JPEG files are rendered from the production `WorkspaceRootView` by `WorkspaceVisualRegressionTests`. JPEG keeps each human-reviewable baseline compact; comparison happens after decoding both images into the same canonical pixel format.

## Generate or update

```sh
UPDATE_VISUAL_GOLDENS=1 swift test --filter WorkspaceVisualRegressionTests
```

Review every changed image before committing it. A changed baseline is an explicit product decision, not routine test maintenance.

## Determinism controls

- External Stage, OBS, VTuber, speech, and SignalDeck activity is not started.
- Background animation and macOS motion are disabled.
- Fixtures derive from the versioned default workspace state, replace its terminal with a static note, and do not launch agent or terminal processes.
- The Aurora theme supplies a deterministic production backdrop; the separate background render sweep covers every theme.
- The command-review fixture freezes the destructive-action confirmation state before any workspace mutation occurs.
- The command-intent fixture captures the live, non-mutating plan shown while the operator is still typing.
- Logical viewport size is independent from PNG output scale, allowing wide-layout coverage without oversized artifacts.

The comparison canonicalizes both images into 8-bit sRGB RGBA pixels. It fails on changed dimensions or when either the mean channel difference or changed-pixel budget is exceeded. Failure output is written beneath `Tests/VisualGoldens/Failures/`.
