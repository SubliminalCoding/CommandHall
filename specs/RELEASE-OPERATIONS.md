# CommandHall release operations

## Version source

`VERSION` is the human-readable application version. `scripts/build-app.sh` writes it into `CFBundleShortVersionString`; `SPATIAL_WORKSPACE_BUILD_NUMBER` overrides the default Git commit count used for `CFBundleVersion`.

Before tagging a release:

1. update `VERSION`;
2. confirm that `COMMERCIAL-LICENSE.md` matches the license published on BilbroSwagginz.com;
3. run `scripts/ci.sh` on macOS;
4. run `scripts/acceptance.sh` on the signing machine;
5. tag exactly `v$(<VERSION)`.

The version must match the customer archive name and website SKU.

## CI boundary

`.github/workflows/ci.yml` has read-only repository permission and no secrets. It runs on GitHub's Apple-silicon `macos-14` runner, compares the checked-in production-view goldens, exercises the durable worker, release-compiles every executable, verifies the assembled bundle, and launches the packaged app in its isolated smoke mode. Visual diff files are uploaded only when CI fails. CI does not publish customer binaries.

## Protected release environment

`.github/workflows/release.yml` uses the GitHub `release` environment and needs these secrets:

- `CERTIFICATE_P12_BASE64`
- `CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `SIGNING_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_PASSWORD`
- `APPLE_TEAM_ID`

The job imports the Developer ID certificate into a temporary keychain, runs the test suite and detached-worker end-to-end check, signs the app and both embedded helpers with Hardened Runtime, submits the archive to Apple, staples and validates the ticket, and creates a SHA-256 checksum. It does not publish a public GitHub release.

Local packaging uses the same path:

```sh
SPATIAL_WORKSPACE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
SPATIAL_WORKSPACE_NOTARY_KEYCHAIN_PROFILE=commandhall \
scripts/package-release.sh
```

Without the keychain profile, the script creates a signed package and checksum but reports that notarization was skipped. `COMMERCIAL-LICENSE.md` is included in every archive as `LICENSE.md`.

After notarization, copy the verified archive into the BilbroSwagginz.com private release assets, confirm its checksum, deploy the site with the release-readiness gate enabled, and complete a real checkout/download test.

## Updates and crash diagnostics

Workspace Settings → Release diagnostics shows the packaged version/build, opens the authoritative CommandHall product page, and lists local `CommandHall` crash reports from the last 30 days. Legacy `SpatialWorkspace` crash reports remain visible after the rename. The app never uploads crash logs, prompts, workspace history, or memory automatically.

Automatic updates are not implemented. Installing an update is an explicit download from GitHub Releases.

## Distribution identity

The public product name is `CommandHall`, the app bundle is `CommandHall.app`, and the bundle identifier is `com.bilbroswagginz.commandhall`. Internal Swift modules, helper names, and the existing Application Support directory remain unchanged so the rename does not invalidate runtime state.

The customer archive contains the signed application and commercial license only. Source export is outside the current release plan.
