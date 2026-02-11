#!/usr/bin/env bash
set -euo pipefail

TEAM_ID="${TEAM_ID:-team_WyEUto2LaQ6c2X0HMRmjtNtV}"
PROJECT_NAMES=("web-app" "web-app-india-preview")
PR_ID=""
GITHUB_USER=""
LIMIT="${LIMIT:-10}"
FETCH_LIMIT="${FETCH_LIMIT:-50}"

usage() {
  cat <<'USAGE'
Usage: scripts/vercel-deployments-test.sh [--pr <number>] [--limit <n>]

Fetches recent Vercel deployments for the configured team + projects.

Options:
  --pr <number>    Filter deployments for a GitHub PR (client-side match against deployment meta)
  --user <login>   Filter deployments for a GitHub username/login (client-side match against deployment meta)
  --limit <n>      Max deployments per project (default: 10; override with LIMIT env var)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      PR_ID="${2:-}"; shift 2 ;;
    --user)
      GITHUB_USER="${2:-}"; shift 2 ;;
    --limit)
      LIMIT="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1"
      usage
      exit 1
      ;;
  esac
done

export LIMIT PR_ID GITHUB_USER

if [[ -z "${VERCEL_TOKEN:-}" ]]; then
  read -rsp "Enter Vercel token: " VERCEL_TOKEN
  echo ""
  if [[ -z "${VERCEL_TOKEN}" ]]; then
    echo "Missing Vercel token."
    exit 1
  fi
fi

api_get() {
  local url="$1"
  local response body status
  response="$(curl -sS -w "\n__HTTP_STATUS__:%{http_code}" \
    -H "Authorization: Bearer ${VERCEL_TOKEN}" \
    -H "Content-Type: application/json" \
    "$url")"

  status="${response##*$'\n__HTTP_STATUS__:'}"
  body="${response%$'\n__HTTP_STATUS__:'*}"

  if [[ "$status" != "200" ]]; then
    echo "Request failed (${status}) for ${url}"
    echo "$body"
    return 1
  fi
  if [[ -z "$body" ]]; then
    echo "Empty response for ${url}"
    return 1
  fi
  echo "$body"
}

echo "Fetching Vercel project IDs for team ${TEAM_ID}..."

for name in "${PROJECT_NAMES[@]}"; do
  project_json="$(api_get "https://api.vercel.com/v9/projects/${name}?teamId=${TEAM_ID}")"
  project_id="$(
    printf "%s" "$project_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))'
  )"

  if [[ -z "${project_id}" ]]; then
    echo "Project not found: ${name}"
    continue
  fi

  deployments_url="https://api.vercel.com/v6/deployments?teamId=${TEAM_ID}&projectId=${project_id}&limit=${FETCH_LIMIT}"

  echo ""
  echo "Deployments for ${name} (${project_id})${PR_ID:+ PR#${PR_ID}}:"
  api_get "${deployments_url}" | python3 -c "$(cat <<'PY'
import json
import os
import sys

data = json.load(sys.stdin)
deployments = data.get('deployments', [])
pr_filter = os.environ.get('PR_ID', '').strip()
user_filter = os.environ.get('GITHUB_USER', '').strip().lower()
limit = int(os.environ.get('LIMIT', '10'))

def deployment_pr(meta: dict) -> str:
    for k in ('githubPullRequestId', 'githubPrId', 'pullRequestId'):
        v = meta.get(k)
        if v is None:
            continue
        return str(v)
    return ''

def matches_user(meta: dict) -> bool:
    if not user_filter:
        return True
    for k, v in (meta or {}).items():
        if v is None:
            continue
        if not isinstance(v, (str, int, float, bool)):
            continue
        kl = str(k).lower()
        if not kl.startswith('github'):
            continue
        if any(tok in kl for tok in ('author', 'actor', 'sender', 'user', 'login')):
            if user_filter in str(v).lower():
                return True
    return False

out = []
for d in deployments:
    meta = d.get('meta') or {}
    pr = deployment_pr(meta)
    if pr_filter and pr != pr_filter:
        continue
    if not matches_user(meta):
        continue
    out.append(d)

for d in out[:limit]:
    meta = d.get('meta') or {}
    ref = meta.get('githubCommitRef') or meta.get('gitBranch') or ''
    sha = meta.get('githubCommitSha') or meta.get('gitSha') or ''
    sha = sha[:7] if sha else ''
    pr = deployment_pr(meta)
    pr = f' PR#{pr}' if pr else ''
    dep_id = d.get('uid') or d.get('id')
    print(f"- {dep_id} | {d.get('readyState')} | {d.get('url')} | {ref} {sha}{pr}")
PY
)"
done
