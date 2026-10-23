#!/usr/bin/env bash
# Builds a repository with a vendored tree of three local git dependencies,
# then moves the tag of the middle one the way an upstream release bot that
# re-creates its tag does. The commit locked for it can no longer be fetched
# by depth-1 clones of the tag, which is what unpinned-paths is for.
#
# Usage: fixture.sh <dir>   (creates <dir>/work, the repository to check)
set -euo pipefail

root="$1"
mkdir -p "$root"
root="$(cd "$root" && pwd)"

git_() {
  git -c user.name=fixture -c user.email=fixture@example.com \
    -c commit.gpgsign=false -c tag.gpgsign=false "$@"
}

for dep in pinned-a moving pinned-b; do
  git_ init -q "$root/$dep"
  echo one > "$root/$dep/file.txt"
  git_ -C "$root/$dep" add .
  git_ -C "$root/$dep" commit -qm one
  git_ -C "$root/$dep" tag v1
done

git_ init -q "$root/work"
{
  printf 'apiVersion: vendir.k14s.io/v1alpha1\nkind: Config\ndirectories:\n- path: vendor\n  contents:\n'
  for dep in pinned-a moving pinned-b; do
    printf '  - path: example.com/%s\n    git:\n      url: file://%s/%s\n      ref: v1\n      depth: 1\n    excludePaths: [".git/**/*"]\n' \
      "$dep" "$root" "$dep"
  done
} > "$root/work/vendir.yml"

(cd "$root/work" && vendir sync && git_ add -A && git_ commit -qm "vendor deps")

# Upstream re-creates the tag on a new commit.
echo two > "$root/moving/file.txt"
git_ -C "$root/moving" commit -qam two
git_ -C "$root/moving" tag -f v1 > /dev/null
