#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
version=${SPATIAL_WORKSPACE_VERSION:-$(<"$project_root/VERSION")}
dist_dir="$project_root/dist"
app_dir="$project_root/build/CommandHall.app"
archive="$dist_dir/CommandHall-$version-macos-arm64.zip"
license_file="$project_root/COMMERCIAL-LICENSE.md"
staging_root=$(mktemp -d /tmp/commandhall-release.XXXXXX)
staging_dir="$staging_root/CommandHall $version"
trap 'rm -R -- "$staging_root"' EXIT
notary_profile=${SPATIAL_WORKSPACE_NOTARY_KEYCHAIN_PROFILE:-}
notary_keychain=${SPATIAL_WORKSPACE_NOTARY_KEYCHAIN:-}

cd "$project_root"
if [[ ! -f "$license_file" ]]; then
  print -u2 "release packaging blocked: missing COMMERCIAL-LICENSE.md"
  exit 78
fi
scripts/build-app.sh release
codesign --verify --deep --strict --verbose=2 "$app_dir"
scripts/smoke-app.sh "$app_dir"

if [[ -e "$dist_dir" ]]; then
  if [[ -x /usr/bin/trash ]]; then
    /usr/bin/trash "$dist_dir"
  else
    rm -rf -- "$dist_dir"
  fi
fi
mkdir -p "$dist_dir"
mkdir -p "$staging_dir"
cp -R "$app_dir" "$staging_dir/CommandHall.app"
cp "$license_file" "$staging_dir/LICENSE.md"
/usr/bin/ditto -c -k --keepParent "$staging_dir" "$archive"

if [[ -n "$notary_profile" ]]; then
  notary_arguments=(--keychain-profile "$notary_profile" --wait)
  if [[ -n "$notary_keychain" ]]; then
    notary_arguments+=(--keychain "$notary_keychain")
  fi
  xcrun notarytool submit "$archive" "${notary_arguments[@]}"
  xcrun stapler staple "$app_dir"
  xcrun stapler validate "$app_dir"
  rm -f -- "$archive"
  rm -R -- "$staging_dir/CommandHall.app"
  cp -R "$app_dir" "$staging_dir/CommandHall.app"
  /usr/bin/ditto -c -k --keepParent "$staging_dir" "$archive"
else
  print -u2 "Notarization skipped: SPATIAL_WORKSPACE_NOTARY_KEYCHAIN_PROFILE is not set."
fi

(
  cd "$dist_dir"
  shasum -a 256 "${archive:t}" > "${archive:t}.sha256"
)

print "$archive"
