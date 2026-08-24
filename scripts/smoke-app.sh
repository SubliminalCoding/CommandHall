#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
app_dir=${1:-$project_root/build/CommandHall.app}
executable="$app_dir/Contents/MacOS/CommandHall"

if [[ ! -x "$executable" ]]; then
  print -u2 "packaged app executable is missing: $executable"
  exit 66
fi

"$executable" --smoke-test &
app_pid=$!
elapsed=0
while kill -0 "$app_pid" 2>/dev/null; do
  if (( elapsed >= 15 )); then
    kill "$app_pid" 2>/dev/null || true
    print -u2 "packaged app did not finish its smoke launch within 15 seconds"
    exit 1
  fi
  sleep 1
  (( elapsed += 1 ))
done

wait "$app_pid"
print "Packaged app smoke launch passed: $app_dir"
