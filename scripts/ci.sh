#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
cd "$project_root"

zsh -n scripts/*.sh
swift test
swift build -c release --product SpatialWorkspace
swift build -c release --product spatial-agent
swift build -c release --product spatial-runtime-worker
swift build --product spatial-runtime-worker
RUN_DURABLE_WORKER_E2E=1 swift test --filter DurableRuntimeWorkerIntegrationTests

SPATIAL_WORKSPACE_SIGNING_IDENTITY=- scripts/build-app.sh release
codesign --verify --deep --strict --verbose=2 build/CommandHall.app
scripts/smoke-app.sh build/CommandHall.app

expected_version=$(<VERSION)
actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/CommandHall.app/Contents/Info.plist)
if [[ "$actual_version" != "$expected_version" ]]; then
  print -u2 "packaged version mismatch: expected $expected_version, found $actual_version"
  exit 1
fi

print "CI acceptance passed"
