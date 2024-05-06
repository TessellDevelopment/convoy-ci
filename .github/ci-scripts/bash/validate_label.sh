#!/bin/bash

set_label() {
  if [ -f convoy.yaml ]; then
    language=$(yq '.language' convoy.yaml)
    version=$(yq '.version' convoy.yaml)
    if [[ "$language" == "helm" ]]; then
      echo "Helm repo, No validation needed using version as tag."
    elif [[ "$version" != "null" ]]; then
      echo "Version present in convoy.yaml, No validation needed using version as tag."
    else
      if [[ "${BASE_REF}" == "main" ]]; then
        APP_GROUP=$(yq '.appGroup // "tessell"' convoy.yaml)
        URL="http://${CONVOY_DEV_API_ENDPOINT}/devops/applications/app-groups/$APP_GROUP/latest-main-release-label"
        RESPONSE=$(curl -f --location "$URL" --header "x-api-key: ${CONVOY_AUTH_TOKEN}")
        echo "$RESPONSE"
        LABEL=$(echo "$RESPONSE" | jq -r '.["latest-main-release-label"]')
        echo "$LABEL"
        if [[ $LABEL == rel-* ]]; then
            echo "LABEL=$LABEL"
        else
            echo "Response: $LABEL"
            echo "Label does not start with 'rel'. Check response."
            exit 1 
        fi
      else
        LABEL=${BASE_REF}
        echo "LABEL=$LABEL"
      fi
      validate_label "$LABEL"
    fi  
    else
    echo "convoy.yaml not found"
    fi 
}

validate_label() {
  tag=$(echo ${TAG} | cut -d '.' -f 2)
  label=$(echo "$1" | cut -d '.' -f 2)
  if [ "$tag" == "$label" ]; then
      echo "TAG and LABEL are on same release label: $label"
  else
      echo "TAG and LABEL are on different release label. Please check git tag and API response."
      exit 1
  fi   
}

set_label $@