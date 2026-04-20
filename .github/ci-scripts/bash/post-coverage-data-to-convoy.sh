#!/bin/bash
#
# post-coverage-data-to-convoy.sh
# Posts code coverage data to the Convoy API.
#
# Required env vars:
#   API_KEY            Convoy auth token
#   API_URL            Convoy API endpoint  (e.g. http://host/devops/code/coverage)
#   APP_GROUP          App group
#   BRANCH_COVERAGE    "covered missed total percentage"
#   CODE_COVERAGE_S3   S3 bucket for coverage reports
#   COMMIT_HASH        Full git commit hash
#   LABEL              Release label
#   LANGUAGE           Repo language  (e.g. java, bash, python)
#   REPO               Repository name
#   SOURCE_BRANCH      Current branch name
#   STATEMENT_COVERAGE "covered missed total percentage"
#   TAG                Release tag
#
# Optional env vars:
#   BASE_BRANCH        PR base branch  (falls back to SOURCE_BRANCH)

set -euo pipefail

# ── skip if coverage data is absent ──────────────────────────────────────────

if [ -z "${BRANCH_COVERAGE:-}" ] || [ -z "${STATEMENT_COVERAGE:-}" ]; then
  echo "Coverage report not generated. Skipping post call to convoy."
  exit 0
fi

# ── validate required env vars ────────────────────────────────────────────────

errors=()
[ -z "${API_KEY:-}"            ] && errors+=("API_KEY")
[ -z "${API_URL:-}"            ] && errors+=("API_URL")
[ -z "${APP_GROUP:-}"          ] && errors+=("APP_GROUP")
[ -z "${CODE_COVERAGE_S3:-}"   ] && errors+=("CODE_COVERAGE_S3")
[ -z "${COMMIT_HASH:-}"        ] && errors+=("COMMIT_HASH")
[ -z "${LABEL:-}"              ] && errors+=("LABEL")
[ -z "${LANGUAGE:-}"           ] && errors+=("LANGUAGE")
[ -z "${REPO:-}"               ] && errors+=("REPO")
[ -z "${SOURCE_BRANCH:-}"      ] && errors+=("SOURCE_BRANCH")
[ -z "${TAG:-}"                ] && errors+=("TAG")

if [ "${#errors[@]}" -gt 0 ]; then
  echo "Error: the following required environment variables are not set:"
  for var in "${errors[@]}"; do
    echo "  - ${var}"
  done
  exit 1
fi

echo "Coverage report present, sending details to convoy."

# ── resolve base branch ───────────────────────────────────────────────────────

base_branch="${BASE_BRANCH:-${SOURCE_BRANCH}}"

# ── determine S3 report extension by language ─────────────────────────────────

case "${LANGUAGE}" in
  java|bash) report_ext="zip"  ;;
  *)         report_ext="html" ;;
esac

report_path="s3://${CODE_COVERAGE_S3}/${LABEL}/${REPO}/coverage-report-${TAG}.${report_ext}"

# ── split coverage strings into individual fields ────────────────────────────

read -r bc_covered bc_missed bc_total bc_pct <<< "${BRANCH_COVERAGE}"
read -r sc_covered sc_missed sc_total sc_pct <<< "${STATEMENT_COVERAGE}"

# ── build JSON payload ────────────────────────────────────────────────────────

payload=$(jq -n \
  --arg  repoName   "${REPO}" \
  --arg  appGroup   "${APP_GROUP}" \
  --arg  commitHash "${COMMIT_HASH:0:7}" \
  --arg  gitBranch  "${base_branch}" \
  --arg  language   "${LANGUAGE}" \
  --arg  reportPath "${report_path}" \
  --argjson bcCovered "${bc_covered}" \
  --argjson bcSkipped "${bc_missed}" \
  --argjson bcTotal   "${bc_total}" \
  --argjson bcPct     "${bc_pct}" \
  --argjson scCovered "${sc_covered}" \
  --argjson scSkipped "${sc_missed}" \
  --argjson scTotal   "${sc_total}" \
  --argjson scPct     "${sc_pct}" \
  '{
    repoName:   $repoName,
    appGroup:   $appGroup,
    commitHash: $commitHash,
    gitBranch:  $gitBranch,
    language:   $language,
    reportPath: $reportPath,
    branchCoverage: {
      covered:    $bcCovered,
      skipped:    $bcSkipped,
      total:      $bcTotal,
      percentage: $bcPct
    },
    statementCoverage: {
      covered:    $scCovered,
      skipped:    $scSkipped,
      total:      $scTotal,
      percentage: $scPct
    }
  }')

echo "Payload:"
echo "${payload}" | jq .

# ── POST to Convoy API ────────────────────────────────────────────────────────

http_response=$(curl -s -w $'\n%{http_code}' \
  -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d "${payload}" \
  "${API_URL}")

http_code=$(echo "${http_response}" | tail -n1)
body=$(echo "${http_response}"      | sed '$d')

echo "Response (${http_code}): ${body}"

if [ "${http_code}" != "200" ]; then
  echo "API request to convoy failed."
  exit 1
fi
