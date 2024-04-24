 #!/bin/bash
set +e
git remote add upstream ${URL}
git fetch upstream master
git checkout -b ${JIRA_ID}
logs=$(git cherry-pick -m 1 upstream/master)
echo "$logs"
while IFS= read -r line; do
  echo "$line"
  if [[ $line == CONFLICT* ]]; then
    file_path=$(echo "$line" | awk '{print $3}')
    if [[ $file_path == 'Merge' ]]; then
      file_path=$(echo "$line" | awk '{print $6}')
      echo "$file_path"
      git add $file_path
    else
      echo "$file_path"
      git rm $file_path
    fi
  fi
done <<< "$logs"
git add .
git commit -m ${PR_TITLE}
git push origin ${JIRA_ID}

curl -X POST -H "Authorization: token ${GITHUB_TOKEN }" \
  -d "{'title': ${PR_TITLE}, 'head': ${JIRA_ID}, 'base': 'main'}" \
  "https://api.github.com/repos/${REPO}/pulls"