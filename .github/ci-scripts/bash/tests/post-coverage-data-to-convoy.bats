#!/usr/bin/env bats
#
# Unit tests for post-coverage-data-to-convoy.sh
#
# Dependencies: bats-core, jq
#
# Run locally:
#   bats .github/ci-scripts/bash/tests/post-coverage-data-to-convoy.bats

SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/post-coverage-data-to-convoy.sh"

# ── test lifecycle ────────────────────────────────────────────────────────────

setup() {
  TEST_DIR="$(mktemp -d)"
  MOCK_BIN="${TEST_DIR}/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="${MOCK_BIN}:${PATH}"

  cd "$TEST_DIR"

  # Required env vars
  export API_KEY="test-api-key"
  export API_URL="http://convoy.test/devops/code/coverage"
  export APP_GROUP="tessell"
  export BRANCH_COVERAGE="62 30 92 67"
  export CODE_COVERAGE_S3="coverage-bucket"
  export COMMIT_HASH="abcdef1234567890"
  export LABEL="main"
  export LANGUAGE="bash"
  export REPO="test-repo"
  export SOURCE_BRANCH="feature-branch"
  export STATEMENT_COVERAGE="55 37 92 59"
  export TAG="1.0.0"

  # Optional env vars (empty by default; tests override as needed)
  export BASE_BRANCH=""
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── helpers ───────────────────────────────────────────────────────────────────

# Runs the script under kcov when COVERAGE_DIR is set, otherwise runs bare bash.
run_script() {
  if [ -n "${COVERAGE_DIR:-}" ]; then
    run kcov \
      --include-path="${SCRIPT_DIR}" \
      --exclude-path="${SCRIPT_DIR}/tests" \
      "${COVERAGE_DIR}" \
      "$@"
  else
    run bash "$@"
  fi
}

# Stubs curl to return HTTP 200 with a success body.
_mock_curl_success() {
  printf '#!/bin/bash\necho '\''{\"status\":\"ok\"}'\''\nprintf '\''200'\''\n' \
    > "${MOCK_BIN}/curl"
  chmod +x "${MOCK_BIN}/curl"
}

# Stubs curl to return the given HTTP code with an error body.
_mock_curl_failure() {
  local code="${1:-401}"
  cat > "${MOCK_BIN}/curl" <<MOCK
#!/bin/bash
echo '{"error":"unauthorized"}'
printf '${code}'
MOCK
  chmod +x "${MOCK_BIN}/curl"
}

# Stubs curl to capture the JSON payload (-d argument) to a file and return 200.
_mock_curl_capture() {
  local capture_file="${TEST_DIR}/captured_payload"
  cat > "${MOCK_BIN}/curl" <<MOCK
#!/bin/bash
prev=""
for arg in "\$@"; do
  if [ "\${prev}" = "-d" ]; then
    printf '%s' "\${arg}" > '${capture_file}'
  fi
  prev="\${arg}"
done
echo '{"status":"ok"}'
printf '200'
MOCK
  chmod +x "${MOCK_BIN}/curl"
}

# ── skip logic ────────────────────────────────────────────────────────────────

@test "script: exits 0 and skips when BRANCH_COVERAGE is empty" {
  export BRANCH_COVERAGE=""
  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping"* ]]
}

@test "script: exits 0 and skips when STATEMENT_COVERAGE is empty" {
  export STATEMENT_COVERAGE=""
  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping"* ]]
}

# ── required env var validation ───────────────────────────────────────────────

@test "script: exits 1 when API_KEY is missing" {
  unset API_KEY
  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"API_KEY"* ]]
}

@test "script: exits 1 when API_URL is missing" {
  unset API_URL
  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"API_URL"* ]]
}

@test "script: exits 1 when APP_GROUP is missing" {
  unset APP_GROUP
  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"APP_GROUP"* ]]
}

@test "script: exits 1 when LANGUAGE is missing" {
  unset LANGUAGE
  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LANGUAGE"* ]]
}

@test "script: exits 1 when COMMIT_HASH is missing" {
  unset COMMIT_HASH
  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"COMMIT_HASH"* ]]
}

@test "script: exits 1 and lists all missing required vars" {
  unset API_KEY API_URL APP_GROUP LANGUAGE
  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"API_KEY"*   ]]
  [[ "$output" == *"API_URL"*   ]]
  [[ "$output" == *"APP_GROUP"* ]]
  [[ "$output" == *"LANGUAGE"*  ]]
}

# ── branch resolution ─────────────────────────────────────────────────────────

@test "script: uses SOURCE_BRANCH as gitBranch when BASE_BRANCH is empty" {
  export BASE_BRANCH=""
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [ "$(echo "$payload" | jq -r '.gitBranch')" = "feature-branch" ]
}

@test "script: uses BASE_BRANCH as gitBranch when set" {
  export BASE_BRANCH="main"
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [ "$(echo "$payload" | jq -r '.gitBranch')" = "main" ]
}

# ── report path extension ─────────────────────────────────────────────────────

@test "script: java language produces .zip report path" {
  export LANGUAGE="java"
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [[ "$(echo "$payload" | jq -r '.reportPath')" == *.zip ]]
}

@test "script: bash language produces .zip report path" {
  export LANGUAGE="bash"
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [[ "$(echo "$payload" | jq -r '.reportPath')" == *.zip ]]
}

@test "script: python language produces .html report path" {
  export LANGUAGE="python"
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [[ "$(echo "$payload" | jq -r '.reportPath')" == *.html ]]
}

# ── payload content ───────────────────────────────────────────────────────────

@test "script: truncates COMMIT_HASH to 7 chars in payload" {
  export COMMIT_HASH="abcdef1234567890"
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [ "$(echo "$payload" | jq -r '.commitHash')" = "abcdef1" ]
}

@test "script: APP_GROUP and LANGUAGE env vars appear in payload" {
  export APP_GROUP="my-team"
  export LANGUAGE="go"
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [ "$(echo "$payload" | jq -r '.appGroup')"  = "my-team" ]
  [ "$(echo "$payload" | jq -r '.language')"  = "go"      ]
}

@test "script: coverage values are correctly mapped to payload fields" {
  export BRANCH_COVERAGE="62 30 92 67"
  export STATEMENT_COVERAGE="55 37 92 59"
  _mock_curl_capture

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  payload=$(cat "${TEST_DIR}/captured_payload")
  [ "$(echo "$payload" | jq -r '.branchCoverage.covered')"      = "62" ]
  [ "$(echo "$payload" | jq -r '.branchCoverage.skipped')"      = "30" ]
  [ "$(echo "$payload" | jq -r '.branchCoverage.total')"        = "92" ]
  [ "$(echo "$payload" | jq -r '.branchCoverage.percentage')"   = "67" ]
  [ "$(echo "$payload" | jq -r '.statementCoverage.covered')"   = "55" ]
  [ "$(echo "$payload" | jq -r '.statementCoverage.skipped')"   = "37" ]
  [ "$(echo "$payload" | jq -r '.statementCoverage.total')"     = "92" ]
  [ "$(echo "$payload" | jq -r '.statementCoverage.percentage')" = "59" ]
}

# ── HTTP response handling ────────────────────────────────────────────────────

@test "script: exits 0 when API returns HTTP 200" {
  _mock_curl_success

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script: exits 1 when API returns non-200 response" {
  _mock_curl_failure 401

  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"API request to convoy failed"* ]]
}
