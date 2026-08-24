#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
destination=${1:-}
ignore_file="$project_root/.public-source-ignore"
public_readme="$project_root/PUBLIC_README.md"

if [[ -z "$destination" ]]; then
  print -u2 "usage: scripts/export-public-source.sh DESTINATION"
  exit 64
fi

destination=${destination:A}
if [[ "$destination" == "$project_root" || "$destination" == "$project_root"/* ]]; then
  print -u2 "destination must be outside the private repository"
  exit 64
fi

if [[ -e "$destination" ]] && [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  print -u2 "destination must not exist or must be empty: $destination"
  exit 73
fi

if [[ ! -f "$project_root/LICENSE" ]]; then
  print -u2 "public export blocked: choose an open-source license and add LICENSE first"
  exit 78
fi

if [[ ! -f "$ignore_file" || ! -f "$public_readme" ]]; then
  print -u2 "public export blocked: missing public export policy files"
  exit 78
fi

typeset -a excluded_patterns
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  excluded_patterns+=("$pattern")
done < "$ignore_file"

staging_root=$(mktemp -d "${TMPDIR:-/tmp}/commandhall-public-export.XXXXXX")
staging="$staging_root/export"
mkdir -p "$staging"

cleanup() {
  if [[ -n "${staging_root:-}" && -d "$staging_root" ]]; then
    command rm -R -- "$staging_root"
  fi
}
trap cleanup EXIT

cd "$project_root"
git ls-files -z | while IFS= read -r -d '' source; do
  excluded=false
  for pattern in "${excluded_patterns[@]}"; do
    if [[ "$source" == ${~pattern} ]]; then
      excluded=true
      break
    fi
  done
  $excluded && continue

  if [[ -L "$source" ]]; then
    print -u2 "public export blocked: tracked symlink requires review: $source"
    exit 1
  fi

  target="$staging/$source"
  mkdir -p "${target:h}"
  cp -p "$source" "$target"
done

if [[ ! -f "$staging/PUBLIC_README.md" || ! -f "$staging/LICENSE" ]]; then
  print -u2 "public export blocked: public README and LICENSE must be tracked"
  exit 78
fi
mv "$staging/PUBLIC_README.md" "$staging/README.md"

if [[ -e "$staging/COMMERCIAL-LICENSE.md" ]]; then
  print -u2 "public export contains the incompatible commercial license"
  exit 1
fi

typeset -a forbidden_regexes=(
  '[A-Za-z0-9-]+\.ts\.net'
  'spark-[A-Za-z0-9-]+'
)

home_matches=$(rg -n -o '/(Users|home)/[A-Za-z0-9._-]+/' "$staging" --glob '!scripts/export-public-source.sh' || true)
unexpected_home_matches=$(print -r -- "$home_matches" | rg -v '/Users/(example|someone)/|/home/(operator|other|commandhall)/' || true)
if [[ -n "$unexpected_home_matches" ]]; then
  print -u2 "public export contains a private workstation path"
  print -r -- "$unexpected_home_matches" >&2
  exit 1
fi

for pattern in "${forbidden_regexes[@]}"; do
  if rg -l "$pattern" "$staging" --glob '!scripts/export-public-source.sh' >/dev/null; then
    print -u2 "public export contains a private machine or network identifier"
    rg -l "$pattern" "$staging" --glob '!scripts/export-public-source.sh' >&2
    exit 1
  fi
done

if rg -l -i 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' "$staging" --glob '!scripts/export-public-source.sh' >/dev/null; then
  print -u2 "public export contains a value matching a credential signature"
  rg -l -i 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' "$staging" --glob '!scripts/export-public-source.sh' >&2
  exit 1
fi

if (( $+commands[gitleaks] )); then
  report="$staging_root/gitleaks.json"
  if ! gitleaks dir "$staging" --redact --no-banner --report-format json --report-path "$report" >/dev/null 2>&1; then
    print -u2 "public export blocked: gitleaks found credential-shaped content"
    exit 1
  fi
fi

(
  cd "$staging"
  find . -type f ! -name SOURCE-MANIFEST.sha256 -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 > SOURCE-MANIFEST.sha256
)

if [[ -d "$destination" ]]; then
  rmdir "$destination"
fi
mv "$staging" "$destination"
print "Public source export ready: $destination"
