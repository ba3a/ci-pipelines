#!/usr/bin/env bash
# Writes the thin caller workflows from templates/ into every project listed in repos.conf,
# on a branch, and pushes it. You open and merge the pull request.
#
# Usage:
#   scripts/sync.sh [--dry-run] [owner/repo ...]
#
# Environment:
#   PIPELINES_REF   tag or branch of ba3a/ci-pipelines the callers pin to (default: v1)
#   SYNC_BRANCH     branch created in the projects (default: ci/sync-pipelines)
#
# A project whose repos.conf line has a machine author also gets machine-sm.yml, the state machine.
#
# Needs git with credentials that can push to the projects. --dry-run renders into ./out.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ref="${PIPELINES_REF:-v1}"
branch="${SYNC_BRANCH:-ci/sync-pipelines}"
dry_run=false
only=()

for arg in "$@"; do
  case "${arg}" in
    --dry-run) dry_run=true ;;
    *) only+=("${arg}") ;;
  esac
done

render() {
  # render <template> <destination> <base> <java> <turns> <tasks> <machine_author>
  sed \
    -e "s|__PIPELINES_REF__|${ref}|g" \
    -e "s|__BASE_BRANCH__|$3|g" \
    -e "s|__JAVA_VERSION__|$4|g" \
    -e "s|__MAX_TURNS__|$5|g" \
    -e "s|__GRADLE_TASKS__|${6//,/ }|g" \
    -e "s|__MACHINE_AUTHOR__|$7|g" \
    "$1" > "$2"
}

wanted() {
  [ "${#only[@]}" -eq 0 ] && return 0
  local r
  for r in "${only[@]}"; do [ "${r}" = "$1" ] && return 0; done
  return 1
}

while read -r repo base java turns tasks author _; do
  case "${repo}" in ''|'#'*) continue ;; esac
  wanted "${repo}" || continue
  echo "==> ${repo}"

  if "${dry_run}"; then
    dest="${root}/out/${repo}"
    mkdir -p "${dest}/.github/workflows"
  else
    work="$(mktemp -d)"
    git clone --quiet "https://github.com/${repo}.git" "${work}"
    git -C "${work}" checkout --quiet -B "${branch}"
    dest="${work}"
    mkdir -p "${dest}/.github/workflows"
  fi

  render "${root}/templates/issue-teammate.caller.yml" "${dest}/.github/workflows/issue-teammate.yml" \
    "${base}" "${java}" "${turns}" "${tasks}" "${author}"
  render "${root}/templates/gradle-ci.caller.yml" "${dest}/.github/workflows/ci.yml" \
    "${base}" "${java}" "${turns}" "${tasks}" "${author}"
  # A project with a machine author runs the state machine; "-" leaves it out.
  if [ -n "${author}" ] && [ "${author}" != "-" ]; then
    render "${root}/templates/machine-sm.caller.yml" "${dest}/.github/workflows/machine-sm.yml" \
      "${base}" "${java}" "${turns}" "${tasks}" "${author}"
  fi

  # The pre-pipeline copies of the workflows are replaced by the callers.
  if ! "${dry_run}"; then
    git -C "${dest}" rm -q --ignore-unmatch .github/workflows/ai-teammate.yml \
      .github/workflows/github-issue-teammate.yml
    git -C "${dest}" add .github/workflows
    if git -C "${dest}" diff --cached --quiet; then
      echo "    already up to date"
    else
      git -C "${dest}" commit --quiet -m "ci: sync the pipeline callers from ba3a/ci-pipelines@${ref}"
      git -C "${dest}" push --quiet --force-with-lease origin "${branch}"
      echo "    pushed ${branch}: https://github.com/${repo}/compare/${base}...${branch}"
    fi
    rm -rf "${work}"
  else
    echo "    rendered into ${dest}"
  fi
done < "${root}/repos.conf"
