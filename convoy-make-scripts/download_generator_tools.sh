#!/usr/bin/env bash

VERSION=${1}

NEXUS_PASSWORD=${NEXUS_PASSWORD:-${GITHUB_TOKEN}}
NEXUS_USERNAME=${NEXUS_USERNAME:-${GITHUB_USER}}

OPENAPI_GENERATOR_CLI_URL=https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/7.8.0/openapi-generator-cli-7.8.0.jar
NEXUS_URL=${NEXUS_PROTOCOL:-https}://${NEXUS_USERNAME}:${NEXUS_PASSWORD}@${NEXUS_SERVER_ENDPOINT:-nexus.tessell.cloud}/repository/${NEXUS_PULL_REPOS_M2:-tessell-m2-development}

CONVOY_API_SPEC_TRANSPILER_URL=${NEXUS_URL}/convoy/code-generator/convoy-api-spec-transpiler/${VERSION}/convoy-api-spec-transpiler-${VERSION}.jar
CONVOY_OPENAPI_CODE_GENERATOR_URL=${NEXUS_URL}/convoy/code-generator/convoy-openapi-code-generator/${VERSION}/convoy-openapi-code-generator-${VERSION}.jar

function download_jars() {
    echo ${CONVOY_API_SPEC_TRANSPILER_URL}
    curl ${CONVOY_API_SPEC_TRANSPILER_URL} -O
    curl ${CONVOY_OPENAPI_CODE_GENERATOR_URL} -O 
    curl ${OPENAPI_GENERATOR_CLI_URL} -O
}

mkdir generator_tools && cd ./generator_tools 
download_jars
