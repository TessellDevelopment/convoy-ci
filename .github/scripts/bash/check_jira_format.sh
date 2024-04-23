if echo "$SOURCE_BRANCH" | grep -Eq '^revert-'; then
    echo "Revert branch, skipping Format check"
    exit 0
fi
if echo "$SOURCE_BRANCH" | grep -Eq '^(${{vars.SUPPORTED_JIRA_PROJECTS}})'; then
  echo "Branch name starts with 'TS-' or 'SRE-' or 'TDEVOPS-' or 'TOPS-'"
else
  echo "Branch name does not start with $SUPPORTED_JIRA_PROJECTS. Checking PR title format."
  PULL_REQUEST_TITLE="$PR_TITLE"
  PATTERN="($SUPPORTED_JIRA_PROJECTS)-[0-9]+\s\|\s"
  if [[ ! $PULL_REQUEST_TITLE =~ $PATTERN ]]; then
    echo "Error: Pull request title is not in the required format. Please use $SUPPORTED_JIRA_PROJECTS-XXXX format."
    exit 1
  else 
    echo "PR Title is in the valid format."
  fi  
fi