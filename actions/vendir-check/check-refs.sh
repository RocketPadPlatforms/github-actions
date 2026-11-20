#!/usr/bin/env bash
# Usage: check-refs.sh VENDIR_YML LOCK_YML
#
# Fails when a pinned ref in vendir.yml is not what vendir.lock.yml
# records. `vendir sync -l` only reproduces the lock, so without this a
# ref bumped in vendir.yml without a sync goes unnoticed. Needs mikefarah
# yq v4. Skips origin/* refs (meant to move) and entries without a ref or
# tag (manual, refSelection, latest releases).
#
# The lock keeps one describe-style name per commit, so a tag that shares
# its commit with another tag can be recorded under the other name. Only
# then is the tag resolved on the remote with `git ls-remote` and compared
# with the locked commit.

# shellcheck disable=SC2016 # $d in the yq expressions is a yq variable
set -euo pipefail

config=$1
lock=$2

# Assigned first so that set -e stops on a yq error instead of reading
# no entries and passing.
locked_entries=$(yq -r '.directories[] as $d | $d.contents[] |
  $d.path + "/" + .path + "|" + (.git.sha // "") + "|" +
  ((.git.tags // []) | join(",")) + "|" + (.githubRelease.tag // "")' "$lock")
wanted_entries=$(yq -r '.directories[] as $d | $d.contents[] |
  $d.path + "/" + .path + "|" + (.git.url // "") + "|" + (.git.ref // "") + "|" +
  (.githubRelease.tag // "")' "$config")

declare -A sha tags release
while IFS='|' read -r key s t r; do
  [ -n "$key" ] || continue
  sha[$key]=$s
  tags[$key]=$t
  release[$key]=$r
done <<< "$locked_entries"

failed=0
fail() {
  echo "::error::$1: vendir.yml wants $2, lock has $3. Run vendir sync and commit the result."
  failed=1
}

remote_tag_sha() {
  git ls-remote "$1" "refs/tags/$2" "refs/tags/$2^{}" | awk -v ref="refs/tags/$2" '
    $2 == ref { sha = $1 }
    $2 == ref "^{}" { peeled = $1 }
    END { print (peeled != "" ? peeled : sha) }'
}

while IFS='|' read -r key url ref tag; do
  [ -n "$key" ] || continue
  if [ -n "$ref" ]; then
    [[ $ref == origin/* ]] && continue
    if [ -z "${sha[$key]+set}" ]; then
      fail "$key" "$ref" nothing
    elif [[ $ref =~ ^[0-9a-f]{40}$ ]]; then
      [ "$ref" = "${sha[$key]}" ] || fail "$key" "$ref" "${sha[$key]}"
    elif [[ ",${tags[$key]}," != *",$ref,"* ]]; then
      if ! remote=$(remote_tag_sha "$url" "$ref"); then
        echo "::error::$key: could not list the tags of $url."
        failed=1
      elif [ -z "$remote" ]; then
        echo "::error::$key: $ref is not a tag in $url. Pin a tag or a commit SHA."
        failed=1
      elif [ "$remote" != "${sha[$key]}" ]; then
        fail "$key" "$ref" "${tags[$key]:-untagged commit ${sha[$key]}}"
      fi
    fi
  elif [ -n "$tag" ]; then
    if [ -z "${release[$key]+set}" ]; then
      fail "$key" "$tag" nothing
    elif [ "$tag" != "${release[$key]}" ]; then
      fail "$key" "$tag" "${release[$key]:-nothing}"
    fi
  fi
done <<< "$wanted_entries"

exit "$failed"
