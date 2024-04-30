#!/bin/bash

agentBuild() {
  set -e
  installGoDependencies
  ARTIFACT="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  OS=$(echo "$ARTIFACT" | awk -F'[-]' '{print $4}')
  SERVICE=$(echo "$ARTIFACT" | awk -F'[-]' '{print $2}')
  echo $OS
  echo $SERVICE
  echo "Building Service"
  make os=$OS nexus_protocol=${NEXUS_PROTOCOL} nexus_server_endpoint=${NEXUS_SERVER_ENDPOINT} $SERVICE
  set +e
}

cloneHelmTemplate() {
  GITHUB_WORKSPACE=$(pwd)
  CHART_GITHUB_LOCATION=$GITHUB_WORKSPACE
  TEMPLATE_REPO_GITHUB_LOCATION=$GITHUB_WORKSPACE/../convoy-helm-template
  echo "$CHART_GITHUB_LOCATION"
  echo "$TEMPLATE_REPO_GITHUB_LOCATION"
  echo "TEMPLATE_REPO_GITHUB_LOCATION=$TEMPLATE_REPO_GITHUB_LOCATION"
  echo "Cloning convoy-helm-template"
  rm -rf $TEMPLATE_REPO_GITHUB_LOCATION
  template_version=$(yq --exit-status '.convoy-helm-template' Chart.yaml)
  if [ $? -eq 0 ]; then
      echo "convoy-helm-template version: $template_version"
  else
      echo "convoy-helm-template version not found.Exiting."
      exit 1
  fi
  git clone --branch $template_version https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${OWNER}/convoy-helm-template.git $TEMPLATE_REPO_GITHUB_LOCATION
  echo "Copying the service values file"
  cp -r $CHART_GITHUB_LOCATION/services/* $TEMPLATE_REPO_GITHUB_LOCATION/helm-chart/values/apps/
  cp -r $CHART_GITHUB_LOCATION/Chart.yaml $TEMPLATE_REPO_GITHUB_LOCATION/helm-chart/Chart.yaml
  set -e
  cd $TEMPLATE_REPO_GITHUB_LOCATION/scripts
  ls -lrta ../helm-chart/values/apps/
}

configureJava() {
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
  export PATH="/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH"
}

createPipConf() {
  echo "[global]" > pip.conf
  echo "index =  ${NEXUS_PROTOCOL}://${NEXUS_USERNAME}:${NEXUS_PASSWORD}@${NEXUS_SERVER_ENDPOINT}/repository/${NEXUS_PULL_REPOS_PY}/simple" >> pip.conf
  echo "index-url = ${NEXUS_PROTOCOL}://${NEXUS_USERNAME}:${NEXUS_PASSWORD}@${NEXUS_SERVER_ENDPOINT}/repository/${NEXUS_PULL_REPOS_PY}/simple" >> pip.conf
  echo "extra-index-url = https://pypi.org/simple" >> pip.conf
  sudo cp pip.conf /etc/pip.conf
  cat /etc/pip.conf
}

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

dbPluginBuild() {
  set -e
  ARTIFACT="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  createPipConf
  installPythonDependencies $ARTIFACT
  lintCheck
  gradlewPythonwheel
  set +e
}

dockerBuild() {
  set -e
  IMAGE="$1"
  FILE="$4"
  if [[ "$FILE" == "null" || -z "$FILE" ]]; then
    FILE="./Dockerfile"
  fi
  echo "$FILE"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  docker build -f $FILE -t $IMAGE \
              --build-arg NEXUS_PROTOCOL=${NEXUS_PROTOCOL} \
              --build-arg NEXUS_SERVER_ENDPOINT=${NEXUS_SERVER_ENDPOINT} \
              --build-arg NEXUS_USERNAME=${NEXUS_USERNAME} \
              --build-arg NEXUS_PASSWORD=${NEXUS_PASSWORD} .
  imageScan $IMAGE
  set +e
}

dockerMultiBuild() {
  docker buildx rm multi-platform-builder
  docker buildx create --use --platform=linux/arm64,linux/amd64 --name multi-platform-builder
  set -e
  IMAGE="$1"
  FILE="$4"
  requiredInputs="1 4"
  validateInputs "$requiredInputs" "$@" 
  docker buildx build -f $FILE --no-cache -t $IMAGE --platform=linux/amd64,linux/arm64 .
  set +e
}

dockerMilvusBuild() {
  docker buildx rm multi-platform-builder
  docker buildx create --use --platform=linux/arm64,linux/amd64 --name multi-platform-builder
  set -e
  IMAGE="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  AGENT_VERSION=$(yq '.tessellAgentVersion' convoy.yaml)
  TASKHANDLER_VERSION=$(yq '.taskHandlerVersion' convoy.yaml)
  docker buildx build --no-cache -t $IMAGE \
                      --platform linux/amd64 \
                      --build-arg HANDLER_TAG=$TASKHANDLER_VERSION \
                      --build-arg AGENT_TAG=$AGENT_VERSION \
                      --build-arg NEXUS_USERNAME=${NEXUS_USERNAME} \
                      --build-arg NEXUS_PASSWORD=${NEXUS_PASSWORD} \
                      --build-arg GITHUB_USER=${GITHUB_USER} \
                      --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} \
                      --build-arg NEXUS_PROTOCOL=${NEXUS_PROTOCOL} \
                      --build-arg NEXUS_SERVER_ENDPOINT=${NEXUS_SERVER_ENDPOINT} .
  set +e
}

elasticConf() {
  git config --global url."https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com".insteadOf "https://github.com"
  installGoDependencies
  git clone https://github.com/magefile/mage
  cd mage
  go run bootstrap.go
  cd ..
}

elasticAgentBuild() {
  set -e
  IMAGE="$1"
  GOOS=linux GOARCH=amd64 go build .
  dockerBuild "$@"
  set +e
}

elasticBuild() {
  set -e
  IMAGE="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  elasticConf
  echo "----------------------------------------------"
  echo "----------- Building Service -----------------"
  export GOPATH=/home/runner/go/bin
  export PATH=/go/bin:/usr/local/go/bin:/opt/maven/bin:/usr/lib/jvm/java-17-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/runner/go/bin
  cd filebeat
  mage package
  cp ./build/golang-crossbuild/filebeat-linux-amd64 ./filebeat
  echo "----------------------------------------------"
  echo "------------ Building Image ------------------"
  docker build -t $IMAGE .
  cd ..
  elasticTarBuild
  set +e
}

elasticTarBuild() {
  echo "----------------------------------------------"
  echo "---------- Creating Tar Files -----------------"
  PACKAGES_DIR=./filebeat/build/distributions/
  mkdir -p $PACKAGES_DIR
  cp ./filebeat/tessell-filebeat-linux.yml $PACKAGES_DIR/filebeat.yml
  cp ./filebeat/build/golang-crossbuild/filebeat-linux-amd64 $PACKAGES_DIR/filebeat
  cp ./filebeat/filebeat.service $PACKAGES_DIR/filebeat.service
  pushd $PACKAGES_DIR
  tar -zcvf filebeat-linux.tar.gz filebeat.yml filebeat filebeat.service
  popd
  cp ./filebeat/tessell-filebeat-windows.yml $PACKAGES_DIR/filebeat.yml
  cp ./filebeat/build/golang-crossbuild/filebeat-windows-amd64.exe $PACKAGES_DIR/filebeat.exe 
  pushd $PACKAGES_DIR
  tar -zcvf filebeat-windows.tar.gz filebeat.yml filebeat.exe
  popd
}

functionBuild() {
  set -e
  ARTIFACT="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  cd tessell;
  OS=$(echo "$ARTIFACT" | awk -F'[-]' '{print $4}')
  CLOUD=$(echo "$ARTIFACT" | awk -F'[-]' '{print $5}')
  echo $OS
  echo $CLOUD
  make OS=$OS CLOUD=$CLOUD nexus_protocol=${NEXUS_PROTOCOL} nexus_server_endpoint=${NEXUS_SERVER_ENDPOINT} package
  cd ..
  set +e
}

goDockerBuild() {
  set -e
  IMAGE="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  installGoDependencies
  echo "Building the service"
  export PATH=${PATH}:$GOPATH/bin
  git config --global url."https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com".insteadOf "https://github.com"
  ./setup -g -i
  imageScan $IMAGE
  set +e
}

goLibraryBuild() {
  set -e
  ARTIFACT="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  NAME=$(echo "$ARTIFACT" | awk -F '-linux' '{print $1}')
  if [ "$NAME" == "$ARTIFACT" ]; then
      NAME=$(echo "$ARTIFACT" | awk -F '-windows' '{print $1}')
      OS="windows"
  else
      OS="linux"
  fi
  ENGINE=$(echo "$ARTIFACT" | awk -F "$NAME-$OS" '{gsub(/^-|-linux|-windows$/, "", $2); print $2}')
  echo "Name: $NAME, OS: $OS, Engine: $ENGINE"
  if [[ "$ENGINE" == "null" || -z "$ENGINE" ]]; then
    make service os=$OS
  else
    make service os=$OS engine=$ENGINE
  fi
  set +e
}

gradlewMaven() {
  set -e
  ./gradlew mavenPackage --refresh-dependencies --console plain \
    -Pnexus_push_username="${NEXUS_USERNAME}" \
    -Pnexus_push_password="${NEXUS_PASSWORD}" \
    -Pnexus_username="${NEXUS_USERNAME}" \
    -Pnexus_password="${NEXUS_PASSWORD}"
  set +e
}

gradlewMavenDocker() {
  ./gradlew mavenPackage docker --console plain \
    -Pnexus_username="${NEXUS_USERNAME}" \
    -Pnexus_password="${NEXUS_PASSWORD}" 
}

gradlewPythonwheel() {
  ./gradlew pythonWheel docker --console plain \
      -Pnexus_username="${NEXUS_USERNAME}" \
      -Pnexus_password="${NEXUS_PASSWORD}"
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

 helmChartBuild() {
  set -e
  CHART_NAME="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  cd scripts
  ./package-and-push --no-push -n $CHART_NAME
  cd ..
  set +e
}

helmTemplateBuild() {
  if [[ ${CHANGED_FILES_ANY_MODIFIES} == 'true' ]]; then
    CHART_NAME="$1"
    requiredInputs="1"
    validateInputs "$requiredInputs" "$@" 
    cloneHelmTemplate
    echo "Running package and push"
    ./package-and-push --no-push -n $CHART_NAME
    cd $GITHUB_WORKSPACE
    set +e
  fi
}

imageScan(){
  export IMAGE="$1"
  trivy image -f json -o trivy_image_scan_result.json  --severity HIGH,CRITICAL --scanners vuln $IMAGE:latest
  dockle -f json -o dockle_image_scan_result.json $IMAGE:latest
  python3 ./scripts/python/image_scan.py 
}

infraProvisionBuild() {
  set -e
  lintCheck
  IMAGE="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  mkdir -p build/tools
  wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/6.0.0/openapi-generator-cli-6.0.0.jar -O build/tools/openapi-generator-cli-6.0.0.jar
  gradlewPythonwheel
  imageScan $IMAGE
  set +e
}

installGoDependencies() {
  go version
  go install golang.org/x/tools/cmd/goimports@latest
  which go
}

installPythonDependencies() {
  DIR=$1
  if [[ -z "$DIR" ]]; then
    DIR='.'
  fi
  python3 -m pip install --upgrade pip
  python3 -m pip install flake8 pytest twine wheel
  if [ -f "$DIR/requirements.txt" ]; then
    python3 -m pip install -r "$DIR/requirements.txt" --trusted-host ${NEXUS_SERVER_ENDPOINT};
  fi
}

jarBuild() {
  set -e
  VERSION="$3"
  requiredInputs="3"
  validateInputs "$requiredInputs" "$@" 
  ./mvnw package -Dversion=$VERSION
  set +e
}

javaDockerBuild() {
  set -e
  IMAGE="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  configureJava
  gradlewMavenDocker
  imageScan $IMAGE
  set +e
}

javaLibraryBuild() {
  set -e
  configureJava
  gradlewMaven
  set +e
}
         
lintCheck() {
  flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
  flake8 . --count --exit-zero --max-complexity=10 --max-line-length=127 --statistics
}

 makeBuild() {
  set -e
  installGoDependencies
  make service
  ARTIFACT="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  OS=$(echo "$ARTIFACT" | awk -F'[-]' '{print $3}')
  make os=$OS pushprox-client
  make clean
  ls -lrta client-package
  set +e
}

makeImage() {
  set -e
  IMAGE="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  make image
  imageScan $IMAGE
  set +e
}

modifiedDir() {
  directories=$(echo ${CHANGED_AND_MODIFIED_FILES} | tr ' ' '\n' | awk -F'/' '{print $1}' | sort -u)
  directories=$(echo $directories | tr '\n' ' ')
  echo "$directories"
}

mvnwBuild() {
  set -e
  ./mvnw install -Dnative -DskipTests -Dquarkus.native.remote-container-build=true
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

opaBuild() {
  set -e
  setupOpa
  ~/opa build policies --output bundles/opa-policies.tar.gz
  set +e
}

opsImageBuild() {
  set -e
  mvnwBuild
  dockerBuild "$@"
  set +e
}

otelcolBuild() {
  set -e
  ARTIFACT="$1"
  CONFIG="$7"
  requiredInputs="1 7"
  validateInputs "$requiredInputs" "$@" 
  OS=$(echo "$ARTIFACT" | awk -F'[-]' '{print $3}')
  GO111MODULE=on go install go.opentelemetry.io/collector/cmd/builder@v0.96.0
  go install go.opentelemetry.io/collector/cmd/builder@v0.96.0
  cd cmd/builder
  go build .
  cd ../..
  GOOS=$OS GOARCH=amd64 ./cmd/builder/builder --config=$CONFIG
  set +e
}

pythonDockerBuild() {
  set -e
  IMAGE="$1"
  rm pip.conf
  lintCheck
  gradlewPythonwheel
  imageScan $IMAGE
  set +e
}

 pythonLibraryBuild() {
  set -e
  ARTIFACT="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  createPipConf
  installPythonDependencies $ARTIFACT
  lintCheck
  gradlewPythonwheel
  set +e
}

qaBuild(){
  set -e
  requiredInputs="1 3"
  validateInputs "$requiredInputs" "$@" 
  createPipConf
  setupQAEnv
  export GITHUB_TOKEN="${GITHUB_TOKEN}"
  cp configs/qabusiness.json config.json
  source qavenv/bin/activate
  make clients -B
  source qavenv/bin/activate
  python3 ./main.py ./testcases -s -v --dry-run --run-long-tests --business-edition
  deactivate
  if [[ ${CHANGED_FILES_ANY_MODIFIES} == 'true' ]]; then
    cd scripts
    dockerBuild "$@"
    cd ..
  fi
  set +e
}

setupOpa() {
  curl -L -o ~/opa https://openpolicyagent.org/downloads/v0.61.0/opa_linux_amd64_static
  chmod 755 ~/opa
  curl -L -o ~/opa_darwin_amd64 https://openpolicyagent.org/downloads/v0.61.0/opa_darwin_amd64
  curl -L -o ~/opa_darwin_amd64.sha256 https://openpolicyagent.org/downloads/v0.61.0/opa_darwin_amd64.sha256
  ~/opa version
}

setupQAEnv() {
  INSTALL_DIR=/usr/local/bin
  sudo mkdir -p $INSTALL_DIR/openapitools
  curl https://raw.githubusercontent.com/OpenAPITools/openapi-generator/master/bin/utils/openapi-generator-cli.sh > openapi-generator-cli
  sudo cp openapi-generator-cli $INSTALL_DIR/openapitools/openapi-generator-cli
  sudo chmod 755 $INSTALL_DIR/openapitools/openapi-generator-cli
  sudo ln -f -s $INSTALL_DIR/openapitools/openapi-generator-cli $INSTALL_DIR/openapi-generator
  wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/6.0.0/openapi-generator-cli-6.0.0.jar -O openapi-generator-cli.jar
  python3 -m pip cache purge
  sudo mv openapi-generator-cli.jar /usr/local/bin/openapi-generator-cli-6.0.0.jar
  python3 -m pip install --user virtualenv --trusted-host ${NEXUS_SERVER_ENDPOINT}
  python3 -m pip install yq wheel --trusted-host ${NEXUS_SERVER_ENDPOINT}
  python3 -m venv qavenv
  source qavenv/bin/activate
  python3 -m pip install wheel --trusted-host ${NEXUS_SERVER_ENDPOINT}
  python3 -m pip install -r scripts/requirements.txt --trusted-host ${NEXUS_SERVER_ENDPOINT}
  python3 -m pip list | grep harness
  deactivate
}


terraformBuild(){
  set -e
  modifiedDir
  BASE_DIR=$PWD
  BUILD_DIR=$BASE_DIR/build
  mkdir -p $BUILD_DIR
  DIRECTORIES=$(modifiedDir)
  EXCLUDE_DIR=("build",".github",".gitignore","convoy.yaml","README.md")
  for DIR in $DIRECTORIES
  do
    if [[ " ${EXCLUDE_DIR[*]} " != *"$DIR"* ]]; then 
      echo "building  ${DIR}"
      ARTIFACT_FILE=$BUILD_DIR/${DIR}.zip
      cd $BASE_DIR/$DIR
      VERSION=$(yq .version convoy.yaml)
      echo terraform_build $BASE_DIR/$DIR $ARTIFACT_FILE
      terraform_build $PWD $ARTIFACT_FILE
    fi
  done
  ls -lrta $BUILD_DIR
  set +e
}

tsmZipBuild() {
  set -e
  ARTIFACT="$1"
  requiredInputs="1"
  validateInputs "$requiredInputs" "$@" 
  mkdir -p build; cd tsmv101; terraform_build $PWD ../build/$ARTIFACT.zip; cd ../build; ls -l;
  unzip -l $ARTIFACT.zip
  cd ..
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

vssTarBuild() {
  set -e
  ARTIFACT="$1"
  EXTENSION="$2"
  CLOUD=$(echo "$ARTIFACT" | awk -F'[-]' '{print $3}')
  DIR="build_$CLOUD"
  mkdir $DIR
  cp -r  ../tessell-vss/tessell-vss-requestor/TessellVssRequestor.exe ../tessell-vss/tessell-vss-provider/$CLOUD/install-provider $DIR
  cd $DIR
  tar -cf ../$ARTIFACT.$EXTENSION .
  cd ..
  ls
  set +e
}

build() {
  type="$1"
  check=$(grep "$type" convoy.yaml)
  if [[ -z "$check" ]]; then
    return
  fi
  mkdir -p $HOME/.m2
  cp .github/scripts/settings.xml $HOME/.m2/settings.xml
  cat $HOME/.m2/settings.xml
  export PATH=${PATH}:$GOPATH/bin
  echo $PATH
  git config --global url."https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com".insteadOf "https://github.com"
  version=$(yq '.version' convoy.yaml)
  language=$(yq '.language' convoy.yaml)
  if [[ "$language" == "terraform" ]]; then
    terraformBuild
    return
  fi
  yq e ".generates.$type[] | [.name, .buildFunction, .extension, .dockerFile, .filePath, .baseImage, .configFile] | @csv" convoy.yaml | sed 's/,/ /g' > artifacts.txt
  lineNumber=1
  while :; do
    echo ------------------------------
    artifactData=$(sed "$lineNumber!d" artifacts.txt)
    if [[ -z "$artifactData" ]]; then
      break
    fi
    read -r name buildFunction ext file filePath baseImage config <<< "$artifactData"
    echo "Name: $name"
    echo "buildFunction: $buildFunction"
    echo "Ext: $ext"
    echo "Version: $version"
    echo "dockerFile: $file"
    echo "filePath: $filePath"
    echo "baseImage: $baseImage"
    echo "ConfigFile: $config"
    $buildFunction $name $ext $version $file $filePath $baseImage $config
    echo "$type $name done"
    echo ------------------------------
    lineNumber=$((lineNumber+1))
  done
  rm artifacts.txt
}

main() {
  build_function=$1
  set +e
  $build_function "artifacts"
  $build_function "dockerImages"
  $build_function "helmCharts"
  $build_function "terraform"
}

main $@