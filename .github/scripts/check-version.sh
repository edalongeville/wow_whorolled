#!/usr/bin/env bash
# Fails when WhoRolled/ changed since <base> without a `## Version` bump in the .toc.
# Usage: check-version.sh <base-ref>
set -euo pipefail
base="${1:?base ref}"
toc=WhoRolled/WhoRolled.toc

changed=$(git diff --name-only "$base" HEAD -- WhoRolled)
[ -z "$changed" ] && { echo "WhoRolled/ unchanged"; exit 0; }

ver() { sed -n 's/^## Version:[[:space:]]*//p' | tr -d '\r' | head -1; }
old=$(git show "$base:$toc" | ver)
new=$(ver < "$toc")

if [ "$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -1)" = "$new" ] && [ "$old" != "$new" ]; then
  echo "Version bumped: $old -> $new"
else
  echo "::error file=$toc::WhoRolled/ changed but ## Version is still $new (was $old); bump it."
  exit 1
fi
