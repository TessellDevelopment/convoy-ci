#!/bin/bash

check_branch_pr_format() {
  if echo "${HEAD_BRANCH}" | grep -Eq '^revert-'; then
    echo "Revert branch, skipping Format check"
    exit 0
  fi
  if echo "${HEAD_BRANCH}" | grep -Eq "^(${SUPPORTED_JIRA_PROJECTS})"; then
    echo "Branch name starts with 'TS-' or 'SRE-' or 'TDEVOPS-' or 'TOPS-'"
  else
    echo "Branch name does not start with ${SUPPORTED_JIRA_PROJECTS}. Checking PR title format."
    PULL_REQUEST_TITLE="${PR_TITLE}"
    PATTERN="(${SUPPORTED_JIRA_PROJECTS})-[0-9]+\s\|\s"
    if [[ ! $PULL_REQUEST_TITLE =~ $PATTERN ]]; then
      echo "Error: Pull request title is not in the required format. Please use ${SUPPORTED_JIRA_PROJECTS}-XXXX format."
      exit 1
    else 
      echo "PR Title is in the valid format."
    fi  
  fi
}

check_double_commit() {
  if ([[ "${USER}" != "cipipelinetessell" ]]) && ([[ "${HEAD_BRANCH}" == *"double_commit"* ]] || [[ "${PR_TITLE}" == *"Double Commit"* ]]); then
    if ([[ "${HEAD_BRANCH}" == *"revert"* ]] && [[ "${PR_TITLE}" == *"Revert"* ]]); then
      echo "Revert Double commit Branch. Allowed"
    else   
      echo "Exclude Double commit naming in Branch, PR title and try again."
      exit 1
    fi
  else
    echo "No double commit conflicts found in Branch or PR title."
  fi
}

check_existing_branches() {
  branch_to_check=${HEAD_BRANCH}-main-double_commit
  list_of_branches=($(git branch -r | awk -F '/' '{print $2}'))
  for branch in "${list_of_branches[@]}";do
    if [[ "$branch" == "$branch_to_check" ]];then
      echo "Double commit branch with name $branch already exists, please merge and/or delete the branch ";exit 1;
    fi
  done
}

main() {
  function=$1
  $function
}

main "$@"

