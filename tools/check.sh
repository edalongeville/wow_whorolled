#!/usr/bin/env bash
# Runs the same checks as the CI, from the repository root: luacheck and the busted specs.
# Installs the Lua tooling first when it is missing (Debian / Ubuntu: apt; elsewhere it says what
# to install).
#
# Usage: tools/check.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")/.."

missing=()
command -v lua5.1 >/dev/null || missing+=(lua5.1)
command -v luacheck >/dev/null || missing+=(lua-check)
command -v busted >/dev/null || missing+=(lua-busted)

if [ "${#missing[@]}" -gt 0 ]; then
  if [ "${1:-}" = "--no-install" ] || ! command -v apt-get >/dev/null; then
    echo "Missing: ${missing[*]} (Debian / Ubuntu packages; elsewhere install Lua 5.1, luacheck and busted)" >&2
    exit 1
  fi
  sudo=""
  [ "$(id -u)" -ne 0 ] && sudo="sudo"
  $sudo apt-get update -qq
  $sudo apt-get install -y -qq "${missing[@]}"
fi

echo "== luacheck"
luacheck .
echo "== busted"
busted --lua=lua5.1 spec
echo "All checks passed."
