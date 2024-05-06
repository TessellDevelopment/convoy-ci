#!/bin/bash

createPipConf() {
  echo "[global]" > pip.conf
  echo "index =  ${NEXUS_PROTOCOL}://${NEXUS_USERNAME}:${NEXUS_PASSWORD}@${NEXUS_SERVER_ENDPOINT}/repository/${NEXUS_PULL_REPOS_PY}/simple" >> pip.conf
  echo "index-url = ${NEXUS_PROTOCOL}://${NEXUS_USERNAME}:${NEXUS_PASSWORD}@${NEXUS_SERVER_ENDPOINT}/repository/${NEXUS_PULL_REPOS_PY}/simple" >> pip.conf
  echo "extra-index-url = https://pypi.org/simple" >> pip.conf
  sudo cp pip.conf /etc/pip.conf
  cat /etc/pip.conf
}

installAwsCli() {
  curl -L -o install-aws.sh https://raw.githubusercontent.com/unfor19/install-aws-cli-action/master/entrypoint.sh
  chmod +x install-aws.sh
  sudo ./install-aws.sh "v2" "amd64"
  rm install-aws.sh
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

setupTrivyDockle() {
  wget https://github.com/aquasecurity/trivy/releases/download/v0.48.3/trivy_0.48.3_Linux-64bit.deb
  sudo dpkg -i trivy_0.48.3_Linux-64bit.deb
  curl -L -o dockle.deb https://github.com/goodwithtech/dockle/releases/download/v0.4.14/dockle_0.4.14_Linux-64bit.deb
  sudo dpkg -i dockle.deb && rm dockle.deb
  python3 -m pip install slack-sdk==3.26.2 --trusted-host ${NEXUS_SERVER_ENDPOINT};
}

main() {
  function=$1
  $function "${@:2}"
}
main $@