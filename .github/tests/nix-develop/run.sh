#!/usr/bin/env bash
# Runs actions/nix-develop/nix-develop.sh against the test flake next to
# this script and checks what it writes to GITHUB_PATH and GITHUB_ENV.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../../../actions/nix-develop/nix-develop.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0
check() { # description, command...
  local what=$1
  shift
  if "$@"; then
    echo "ok   $what"
  else
    echo "FAIL $what"
    failed=1
  fi
}

# shellcheck disable=SC2329 # called through check
not() { ! "$@"; }

# Whether a GC root points at the target of the given link.
# shellcheck disable=SC2329 # called through check
has_root() { nix-store --query --roots "$(readlink -f "$1")" 2> /dev/null | grep -qF "$1"; }

# Value of a variable in a GITHUB_ENV file written as name<<delimiter.
env_value() {
  awk -v n="$1" 'f && $0 == d { exit } f { print } index($0, n "<<") == 1 { d = substr($0, length(n) + 3); f = 1 }' "$2"
}

hello="$(nix build --no-link --print-out-paths "$here#hello")"

run() { # name, installable, extra PATH
  local name=$1 installable=$2 extra_path=$3 rc=0
  : > "$work/$name.env"
  : > "$work/$name.path"
  mkdir -p "$work/$name.temp"
  GITHUB_ENV="$work/$name.env" GITHUB_PATH="$work/$name.path" PATH="$PATH$extra_path" \
    RUNNER_TEMP="$work/$name.temp" "$script" "$installable" > "$work/$name.out" 2>&1 || rc=$?
  echo "$rc" > "$work/$name.rc"
}

# An existing PATH entry that contains the dev shell's entry as a substring
# must not hide it.
run ok "$here#default" ":$hello/bin-other"
check "exits 0" grep -qx 0 "$work/ok.rc"
check "adds the dev shell's tool to GITHUB_PATH" grep -qxF "$hello/bin" "$work/ok.path"
check "exports a single-line variable" test "$(env_value SINGLE "$work/ok.env")" = one
check "exports a multi-line variable" test "$(env_value MULTI "$work/ok.env")" = $'line1\nline2'
check "keeps the dev shell from being garbage-collected" \
  has_root "$work/ok.temp/nix-develop-profile"
check "prints the shellHook's output" grep -qxF hook=printed "$work/ok.out"
check "does not export the shellHook's output" test -z "$(env_value hook "$work/ok.env")"
for name in TMPDIR TMP TEMP TEMPDIR NIX_BUILD_TOP HOME PWD OLDPWD SHLVL _; do
  check "does not export $name" not grep -q "^$name<<" "$work/ok.env"
done

run bad "$here#nope" ""
check "fails for an unknown installable" not grep -qx 0 "$work/bad.rc"

rc=0
GITHUB_ENV="$work/nonix.env" GITHUB_PATH="$work/nonix.path" PATH="$(dirname "$(command -v bash)")" \
  bash "$script" "$here#default" > "$work/nonix.out" 2>&1 || rc=$?
check "fails without nix" test "$rc" -ne 0
check "explains that nix is missing" grep -qF "::error::" "$work/nonix.out"

if [ "$failed" -ne 0 ]; then
  for f in "$work"/*.out; do
    echo "--- $(basename "$f")"
    cat "$f"
  done
fi
exit "$failed"
