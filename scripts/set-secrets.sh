#!/usr/bin/env bash
# Sets the repository secrets the pipelines need in every project of repos.conf.
# Values come from the environment, never from this repository.
#
# Usage:
#   PAT_TOKEN=... CLAUDE_CODE_API_KEY=... scripts/set-secrets.sh [owner/repo ...]
#
# Needs the GitHub CLI (gh) logged in with a token that may write repository secrets.
set -euo pipefail

command -v gh >/dev/null || { echo "gh (GitHub CLI) is required" >&2; exit 1; }
: "${PAT_TOKEN:?PAT_TOKEN is not set}"
: "${CLAUDE_CODE_API_KEY:?CLAUDE_CODE_API_KEY is not set}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
only=("$@")

wanted() {
  [ "${#only[@]}" -eq 0 ] && return 0
  local r
  for r in "${only[@]}"; do [ "${r}" = "$1" ] && return 0; done
  return 1
}

while read -r repo _; do
  case "${repo}" in ''|'#'*) continue ;; esac
  wanted "${repo}" || continue
  echo "==> ${repo}"
  printf '%s' "${PAT_TOKEN}" | gh secret set PAT_TOKEN --repo "${repo}"
  printf '%s' "${CLAUDE_CODE_API_KEY}" | gh secret set CLAUDE_CODE_API_KEY --repo "${repo}"
done < "${root}/repos.conf"
