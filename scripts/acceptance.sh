#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
cd "$project_root"

swift test
swift build --product spatial-runtime-worker
RUN_DURABLE_WORKER_E2E=1 swift test --filter DurableRuntimeWorkerIntegrationTests
scripts/build-app.sh release
codesign --verify --deep --strict --verbose=2 build/CommandHall.app
scripts/smoke-app.sh build/CommandHall.app

if [[ ! -x build/CommandHall.app/Contents/MacOS/spatial-agent ]]; then
  print -u2 "provider-neutral spatial-agent helper is missing"
  exit 1
fi

if [[ ! -x build/CommandHall.app/Contents/MacOS/spatial-runtime-worker ]]; then
  print -u2 "durable spatial-runtime-worker helper is missing"
  exit 1
fi

if ! build/CommandHall.app/Contents/MacOS/spatial-agent --help | rg -q 'audio status|audio plan|audio apply|audio panic|spatial-agent mcp'; then
  print -u2 "spatial-agent helper does not advertise its bounded command surface"
  exit 1
fi

signature_details=$(codesign --display --verbose=4 build/CommandHall.app 2>&1)
expected_team_id=${SPATIAL_WORKSPACE_EXPECTED_TEAM_ID:-}
if [[ -n "$expected_team_id" ]]; then
  if [[ "$signature_details" != *"TeamIdentifier=$expected_team_id"* || "$signature_details" == *"flags=0x2(adhoc)"* ]]; then
    print -u2 "app is not signed by expected team $expected_team_id"
    exit 1
  fi
fi

entitlements=$(codesign --display --entitlements - build/CommandHall.app 2>/dev/null)
if [[ "$entitlements" != *"com.apple.security.device.audio-input"* ]]; then
  print -u2 "audio-input entitlement is missing"
  exit 1
fi

if otool -L build/CommandHall.app/Contents/MacOS/CommandHall | rg -i 'node|electron|clawstudio|cursor'; then
  print -u2 "unexpected external runtime dependency found"
  exit 1
fi

if rg -n -i 'TODO|FIXME|STUB|PLACEHOLDER|MOCK|DUMMY|FAKE|not implemented' Sources; then
  print -u2 "incomplete implementation marker found"
  exit 1
fi

print "Acceptance passed: $project_root/build/CommandHall.app"
