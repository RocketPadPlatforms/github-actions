#!/usr/bin/env bash
# Runs actions/vendir-check/check-refs.sh on each fixture: `ok` must pass,
# every other case must fail with its expected message. Fixtures that need
# a remote point at a local repository built here (@REPO@, @SHA1@, @SHA2@).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
check="$here/../../../actions/vendir-check/check-refs.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
git init -q "$repo"
g() { git -C "$repo" -c user.name=test -c user.email=test@invalid "$@"; }
g commit -q --allow-empty -m first
g tag -a -m v1.0.0 v1.0.0
g tag -a -m pkg/v1.0.0 pkg/v1.0.0
sha1="$(g rev-parse HEAD)"
g commit -q --allow-empty -m second
g tag -a -m v2.0.0 v2.0.0
g branch release
sha2="$(g rev-parse HEAD)"

failed=0
expect() {
  local case=$1 want_rc=$2 want=$3 out rc=0 f
  mkdir -p "$work/$case"
  for f in vendir.yml vendir.lock.yml; do
    sed -e "s|@REPO@|file://$repo|g" -e "s|@SHA1@|$sha1|g" -e "s|@SHA2@|$sha2|g" \
      "$here/$case/$f" > "$work/$case/$f"
  done
  out="$("$check" "$work/$case/vendir.yml" "$work/$case/vendir.lock.yml" 2>&1)" || rc=$?
  if [ "$rc" -ne "$want_rc" ] || ! grep -qF -- "$want" <<< "$out"; then
    echo "FAIL $case: exit $rc (want $want_rc), output:"
    echo "$out"
    failed=1
  else
    echo "ok   $case"
  fi
}

expect ok 0 ""
expect tag-drift 1 "vendor/loki: vendir.yml wants v2.0.0, lock has v1.0.0. Run vendir sync"
expect branch-ref 1 "vendor/traefik: release is not a tag in file://$repo. Pin a tag or a commit SHA."
expect sha-drift 1 "vendor/pinned: vendir.yml wants 0123456789abcdef0123456789abcdef01234567, lock has fedcba9876543210fedcba9876543210fedcba98"
expect release-drift 1 "vendor/secretgen: vendir.yml wants v0.22.0, lock has v0.21.4"
expect missing 1 "vendor/added: vendir.yml wants v1.0.0, lock has nothing"
expect unreachable 1 "vendor/gone: could not list the tags of file://$repo-missing"
expect unparsable 1 "Error"

exit "$failed"
