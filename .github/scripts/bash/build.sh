#!/bin/bash

configureNpmrc(){
  set +e 
  REPO="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  rm ~/.npmrc
  TOKEN=$(echo -n "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" | base64 -w 0)
  echo "//${NEXUS_SERVER_ENDPOINT}/repository/:_auth = $TOKEN" >> ~/.npmrc
  echo "//${NEXUS_SERVER_ENDPOINT}/repository/:always-auth = true" >> ~/.npmrc 
  echo "@tessell:registry=${NEXUS_PROTOCOL}://${NEXUS_SERVER_ENDPOINT}/repository/$REPO" >> ~/.npmrc
  cat ~/.npmrc
}

gradlewUIBuild() {
  rm ~/.npmrc
  rm ~/.yarnrc
  TOKEN=$(echo -n "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" | base64 -w 0)
  echo "\"@tessell:registry\" \"${NEXUS_PROTOCOL}://${NEXUS_SERVER_ENDPOINT}/repository/${NEXUS_PUSH_REPOS_NPM}/\"" >> .yarnrc
  echo "always-auth=true" >> .npmrc
  echo "_auth=$TOKEN" >> .npmrc
  cat .npmrc
  cat .yarnrc
  set -e
  ENV_JSON=${TESSELL_UI_ENV_SECRET}
  echo "$ENV_JSON" | jq -r 'to_entries | .[] | "\(.key)=\"\(.value)\"" ' | sed '1s/^/\n/' >> .env
  cat .env
  ./gradlew zipUiBuild --console plain --stacktrace \
    -Pnexus_username="${NEXUS_USERNAME}" \
    -Pnexus_password="${NEXUS_PASSWORD}"
  set +e
}

gradlewUIBuildAndPush() {
  gradlewUIBuild "$@"
  set -e
  ./gradlew publish --console plain \
    -Pnexus_push_username="${NEXUS_USERNAME}" \
    -Pnexus_push_password="${NEXUS_PASSWORD}" \
    -Pnexus_username="${NEXUS_USERNAME}" \
    -Pnexus_password="${NEXUS_PASSWORD}" \
    -Pnexus_push_repo_m2="${NEXUS_PUSH_REPOS_M2}" \
    -Pnexus_pull_repo_m2="${NEXUS_PULL_REPOS_M2}"
  set +e
}

npmBuild() {
  set -e
  npm install
  npm run build
  configureNpmrc "${NEXUS_REPO_NPM}"
  set -e
  version="$3"
  requiredInputs="3"
  validateInputs "$requiredInputs" "$@" 
  yq ".version = \"$version\"" package.json > tmp_package.json
  mv tmp_package.json package.json
  npm publish   
  set +e
}

npmBuildAndPush() {
  set -e
  npm install
  npm run build
  configureNpmrc "${NEXUS_PUSH_REPOS_NPM}"
  set -e
  version="$3"
  requiredInputs="3"
  validateInputs "$requiredInputs" "$@" 
  yq ".version = \"$version\"" package.json > tmp_package.json
  mv tmp_package.json package.json
  npm publish   
  set +e
}

validateInputs() {
  local required=($1)
  shift
  for index in "${required[@]}"; do
    if [ -z "${!index}" ]; then
      echo "Error: Required Argument at index $index is null or empty."
      exit 1
    fi
  done
}

main() {
  build_function=$1
  $build_function ${@:2}
}
main $@