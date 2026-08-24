#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
configuration=${1:-debug}

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
  print -u2 "usage: scripts/build-app.sh [debug|release]"
  exit 64
fi

cd "$project_root"
swift build -c "$configuration"

build_dir=$(swift build -c "$configuration" --show-bin-path)
app_dir="$project_root/build/CommandHall.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
entitlements="$project_root/support/SpatialWorkspace.entitlements"
signing_identity=${SPATIAL_WORKSPACE_SIGNING_IDENTITY:--}
version=${SPATIAL_WORKSPACE_VERSION:-$(<"$project_root/VERSION")}
build_number=${SPATIAL_WORKSPACE_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || print 1)}

if [[ "$signing_identity" != "-" ]] && ! security find-identity -v -p codesigning | grep -Fq "\"$signing_identity\""; then
  print -u2 "Missing identity: $signing_identity"
  print -u2 "Set SPATIAL_WORKSPACE_SIGNING_IDENTITY=- for an ad-hoc local build."
  exit 78
fi

if [[ -e "$app_dir" ]]; then
  if [[ -x /usr/bin/trash ]]; then
    /usr/bin/trash "$app_dir"
  else
    rm -rf -- "$app_dir"
  fi
fi
mkdir -p "$macos_dir" "$resources_dir"
cp "$build_dir/SpatialWorkspace" "$macos_dir/CommandHall"
cp "$build_dir/spatial-agent" "$macos_dir/spatial-agent"
cp "$build_dir/spatial-runtime-worker" "$macos_dir/spatial-runtime-worker"
cp -R "$build_dir/SpatialWorkspace_SpatialWorkspaceApp.bundle" "$resources_dir/SpatialWorkspace_SpatialWorkspaceApp.bundle"
cp "$project_root/support/CommandHall.icns" "$resources_dir/CommandHall.icns"
cp "$project_root/support/Info.plist" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_dir/Info.plist"

signing_options=(--force --options runtime --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
  signing_options+=(--timestamp)
fi

codesign \
  "${signing_options[@]}" \
  "$macos_dir/spatial-agent"

codesign \
  "${signing_options[@]}" \
  "$macos_dir/spatial-runtime-worker"

codesign \
  "${signing_options[@]}" \
  --entitlements "$entitlements" \
  "$app_dir"
print "$app_dir"
