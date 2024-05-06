#!/bin/bash

check_commits() {
  PR_COMMITS=$(curl -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      ${GH_API_URL}/repos/${REPO}/pulls/${PR_NUMBER}/commits| jq -r '. | length')
  echo "Number of commits in PR: $PR_COMMITS"
  return $PR_COMMITS
}

check_approval() {
  if [[ "${PR_TITLE}" == *"double_commit"* && "${USER}" == "cipipelinetessell" ]]; then
    PR_COMMITS= check_commits()
    if [ "$PR_COMMITS" -eq 1 ]; then
      echo "One Commit present in DC."
      exit 0
    else
      echo "More than one commit present in DC, need approval."
    fi
  fi
  PAGE_NUMBER=1
  ALL_REVIEWERS=""
  while true; do
    echo $PAGE_NUMBER
    REVIEWERS=$(curl -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${GH_API_URL}/repos/${REPO}/pulls/${PR_NUMBER}/reviews?per_page=100&page=$PAGE_NUMBER" | jq -r '.[] | select(.state == "APPROVED") | .user.login')
    if [ -z "$REVIEWERS" ]; then
      break
    fi
    ALL_REVIEWERS+="$REVIEWERS"
    ((PAGE_NUMBER++))
  done
  IFS=, read -r -a REVIEWER_ARRAY <<< "$(echo -e "$ALL_REVIEWERS" | tr '\n' ',')"
  IFS=' ' read -ra TEAMS_ARRAY <<< "$TEAMS"
  for TEAM in "${TEAMS_ARRAY[@]}"; do
    FLAG=0
    MEMBERS=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" "${GH_API_URL}/orgs/${OWNER}/teams/${TEAMS}/members" | jq -r '.[].login')
    IFS=, read -r -a MEMBER_ARRAY <<< "$(echo -e "$MEMBERS" | tr '\n' ',')"
    for REVIEWER in "${REVIEWER_ARRAY[@]}"; do
      for MEMBER in "${MEMBER_ARRAY[@]}"; do
        if [ "$REVIEWER" == "$MEMBER" ]; then
          echo "Review Approved by: $REVIEWER"
          FLAG=1
        fi
      done
    done
    if [ $FLAG -eq 0 ]; then
      echo "Approval not present for $TEAM team."
      exit 1
    fi
  done
}

main() {
  function=$1
  $function "${@:2}"
}

main "$@"

