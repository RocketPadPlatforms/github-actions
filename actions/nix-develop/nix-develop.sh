#!/usr/bin/env bash
# Loads the environment of a flake dev shell into the job: its PATH entries
# go to GITHUB_PATH, its other variables to GITHUB_ENV.
set -euo pipefail

installable="${1:-.#default}"

if ! command -v nix > /dev/null; then
  echo "::error::nix is not on PATH. Use a runner with Nix (the nix label on the self-hosted runners) or install it first, e.g. with cachix/install-nix-action." >&2
  exit 1
fi

# The temporary directories of `nix develop`, deleted when it exits, and
# variables that belong to the runner or the shell.
skip=" TMPDIR TMP TEMP TEMPDIR NIX_BUILD_TOP HOME PWD OLDPWD SHLVL _ "

env_file="$(mktemp)"
trap 'rm -f "$env_file"' EXIT

# The profile is a GC root that keeps the dev shell's store paths for the
# rest of the job; the runner empties RUNNER_TEMP after each job. The NUL
# separates what a shellHook prints from the environment.
nix develop "$installable" --profile "${RUNNER_TEMP:?}/nix-develop-profile" \
  --command bash -c 'printf "\0"; env -0' > "$env_file"

new_path=()
exported=0
{
  IFS= read -r -d '' hook_output || true
  if [ -n "$hook_output" ]; then
    printf '%s' "$hook_output"
  fi

  while IFS= read -r -d '' entry; do
    name="${entry%%=*}"
    value="${entry#*=}"

    if [ "$name" = PATH ]; then
      IFS=: read -r -a entries <<< "$value"
      for dir in "${entries[@]}"; do
        if [ -n "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
          new_path+=("$dir")
        fi
      done
      continue
    fi

    # Exported shell functions (BASH_FUNC_name%%) are not variables.
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ "$skip" != *" $name "* ]] || continue
    if [ -n "${!name+set}" ] && [ "${!name}" = "$value" ]; then
      continue
    fi

    delimiter="EOF_$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    printf '%s<<%s\n%s\n%s\n' "$name" "$delimiter" "$value" "$delimiter" >> "$GITHUB_ENV"
    exported=$((exported + 1))
  done
} < "$env_file"

# Each line of GITHUB_PATH is put in front of PATH, so write them in
# reverse to keep the dev shell's order.
for ((i = ${#new_path[@]} - 1; i >= 0; i--)); do
  echo "${new_path[$i]}" >> "$GITHUB_PATH"
done

echo "Loaded $installable: ${#new_path[@]} PATH entries, $exported variables."
