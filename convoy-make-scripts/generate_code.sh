

function generate_code() {
    set -ex
    export GO_POST_PROCESS_FILE="$(which gofmt) -w"
    CONVOY_CODE_GENERATOR_VERSION=${1}
    API_SPEC_FILE=${2} #./api-spec.yaml
    GENERATED_PACKAGE_NAME=${3} #generated
    GENERATED_FOLDER=${4}
    OPENAPI_GENERATOR=${5} #go-fiber
    OPENAPI_SPEC_FILE=${6} #./generator_tools/transpiledOpenApiSpec.yaml
    MODULE=${7} #convoy-rms
    set -ex
    java -cp "generator_tools/convoy-api-spec-transpiler-${CONVOY_CODE_GENERATOR_VERSION}.jar" com.convoy.Main \
        ${API_SPEC_FILE} ${OPENAPI_SPEC_FILE}
    java -cp "generator_tools/convoy-openapi-code-generator-${CONVOY_CODE_GENERATOR_VERSION}.jar:generator_tools/openapi-generator-cli-7.8.0.jar" \
        org.openapitools.codegen.OpenAPIGenerator generate -g ${OPENAPI_GENERATOR} \
                -o ${GENERATED_FOLDER}  \
                -i ${OPENAPI_SPEC_FILE} \
                -e pebble \
                --package-name ${GENERATED_PACKAGE_NAME} \
                --artifact-id ${MODULE} \
                --enable-post-process-file \
                --additional-properties "enumClassPrefix=true" \
                --skip-validate-spec \
                    --global-property="skipFormModel=false"
}

function generate_client_code() {
    set -ex
    for client in ${CLIENTS}; do
        CLIENT_SNAKE=$(echo ${client} | tr '-' '_')
        generate_code ${CONVOY_CODE_GENERATOR_VERSION} "client-specs/${client}-api-spec.yaml" "${CLIENT_SNAKE}_client" "generated-clients/${client}" "convoy-go-client" "generator_tools/${client}-api-spec-transpiled.yaml" ${client}
    done
}

function download_client_spec() {
    mkdir -p client-specs
    for client in ${CLIENTS}; do
        curl -H "Authorization: token ${GITHUB_TOKEN}" \
            https://raw.githubusercontent.com/TessellDevelopment/${client}/main/api-spec.yaml \
            -o "client-specs/${client}-api-spec.yaml"
    done
}

$*
