#!/usr/bin/env bats
#
# Unit tests for check-version-in-nexus.sh
#
# Dependencies: bats-core, jq, yq
#
# Run locally:
#   bats .github/ci-scripts/bash/tests/check-version-in-nexus.bats

SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/check-version-in-nexus.sh"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

# ── test lifecycle ────────────────────────────────────────────────────────────

setup() {
  TEST_DIR="$(mktemp -d)"
  MOCK_BIN="${TEST_DIR}/mock-bin"
  mkdir -p "$MOCK_BIN"
  # Stubs placed here shadow real commands for the duration of each test.
  export PATH="${MOCK_BIN}:${PATH}"

  # Run all script tests from the temp dir so ./convoy.yaml resolves correctly.
  cd "$TEST_DIR"

  # Required env vars (no real Nexus needed; curl is always stubbed).
  export NEXUS_URL="http://nexus.test/service/rest/v1/search?repository"
  export NEXUS_USERNAME="user"
  export NEXUS_PASSWORD="pass"
  export NEXUS_PUSH_REPOS_M2="m2-releases"
  export NEXUS_PUSH_REPOS_PY="py-releases"
  export MODIFIED_FILES=""
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── helpers ───────────────────────────────────────────────────────────────────

# Runs the script under kcov when COVERAGE_DIR is set, otherwise runs bare bash.
# kcov merges data across invocations into the same output directory.
run_script() {
  if [ -n "${COVERAGE_DIR:-}" ]; then
    # Execute the script directly (not via 'bash script.sh') so kcov reads the
    # #!/bin/bash shebang and activates its BASH_ENV injection engine rather than
    # treating 'bash' as an opaque ELF binary with no script coverage info.
    run kcov \
      --include-path="${SCRIPT_DIR}" \
      --exclude-path="${SCRIPT_DIR}/tests" \
      "${COVERAGE_DIR}" \
      "$@"
  else
    run bash "$@"
  fi
}

# Stubs curl to return the contents of the given JSON file, ignoring all args.
_mock_curl() {
  local response_file="$1"
  printf '#!/bin/bash\ncat %s\n' "$response_file" > "${MOCK_BIN}/curl"
  chmod +x "${MOCK_BIN}/curl"
}

# Stubs curl to return page1 on the first call and page2 on subsequent calls
# (detected by the presence of "continuationToken" in the argument list).
_mock_curl_paginated() {
  local page1="$1"
  local page2="$2"
  cat > "${MOCK_BIN}/curl" <<EOF
#!/bin/bash
case "\$*" in
  *continuationToken*) cat '${page2}' ;;
  *)                   cat '${page1}' ;;
esac
EOF
  chmod +x "${MOCK_BIN}/curl"
}

# ── jq logic: maven2 exact-match (the false-positive fix) ────────────────────
# These tests validate the jq queries used inside check_page() directly,
# independently of the script, to document the fix for the grep false-positive.

@test "jq/maven2: exact artifact name returns count 1" {
  run jq -r --arg name "svc-bulk-create-attach-empty-volume-azure" \
    '[.items[] | select(.name == $name)] | length' \
    "${FIXTURES}/nexus/maven2-match.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "jq/maven2: superstring 'gcpcore-svc-bulk-...' does NOT match 'svc-bulk-...'" {
  # grep 'svc-bulk-create-attach-empty-volume-azure' would match the gcpcore- prefixed
  # variant (substring). jq select(.name == $name) must not.
  run jq -r --arg name "svc-bulk-create-attach-empty-volume-azure" \
    '[.items[] | select(.name == $name)] | length' \
    "${FIXTURES}/nexus/maven2-similar.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "jq/maven2: no match returns count 0" {
  run jq -r --arg name "svc-bulk-create-attach-empty-volume-azure" \
    '[.items[] | select(.name == $name)] | length' \
    "${FIXTURES}/nexus/empty.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

# ── jq logic: python PEP 508 name normalisation ───────────────────────────────

@test "jq/python: hyphen in nexus name matches underscore in query (PEP 508)" {
  # Nexus stores 'my-package'; script normalises to 'my_package' before querying.
  # The jq filter must normalise both sides so they compare equal.
  run jq -r --arg name "my_package" \
    '[.items[] | select(
        (.name | gsub("[-_.]"; "_") | ascii_downcase)
        == ($name | gsub("[-_.]"; "_") | ascii_downcase)
     )] | length' \
    "${FIXTURES}/nexus/python-hyphen.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "jq/python: case difference in name is normalised (PEP 508)" {
  run jq -r --arg name "MY_PACKAGE" \
    '[.items[] | select(
        (.name | gsub("[-_.]"; "_") | ascii_downcase)
        == ($name | gsub("[-_.]"; "_") | ascii_downcase)
     )] | length' \
    "${FIXTURES}/nexus/python-hyphen.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "jq/python: unrelated package name returns count 0" {
  run jq -r --arg name "other-package" \
    '[.items[] | select(
        (.name | gsub("[-_.]"; "_") | ascii_downcase)
        == ($name | gsub("[-_.]"; "_") | ascii_downcase)
     )] | length' \
    "${FIXTURES}/nexus/python-hyphen.json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

# ── script: missing convoy.yaml ───────────────────────────────────────────────

@test "script: exits 0 and skips when convoy.yaml is absent" {
  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"convoy.yaml not found"* ]]
}

# ── script: java (maven2) ─────────────────────────────────────────────────────

@test "script/java: exits 0 when version is not in Nexus" {
  cp "${FIXTURES}/convoy-java.yaml" convoy.yaml
  _mock_curl "${FIXTURES}/nexus/empty.json"

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "script/java: exits 1 when version already exists in Nexus" {
  cp "${FIXTURES}/convoy-java.yaml" convoy.yaml
  _mock_curl "${FIXTURES}/nexus/maven2-match.json"

  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "script/java: superstring artifact in Nexus does not block merge (no false positive)" {
  # Nexus contains 'gcpcore-svc-bulk-...'; checking for 'svc-bulk-...' should pass.
  cp "${FIXTURES}/convoy-java.yaml" convoy.yaml
  _mock_curl "${FIXTURES}/nexus/maven2-similar.json"

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "script/java: exits 0 when version field is missing in convoy.yaml" {
  cp "${FIXTURES}/convoy-java-no-version.yaml" convoy.yaml

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing"* ]]
}

# ── script: python ────────────────────────────────────────────────────────────

@test "script/python: exits 0 when version is not in Nexus" {
  cp "${FIXTURES}/convoy-python.yaml" convoy.yaml
  _mock_curl "${FIXTURES}/nexus/empty.json"

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "script/python: exits 1 when Nexus has hyphenated name matching normalised query" {
  # convoy.yaml artifact 'my-package' → normalised to 'my_package'.
  # Nexus stores 'my-package'. PEP 508 normalisation must match them.
  cp "${FIXTURES}/convoy-python.yaml" convoy.yaml
  _mock_curl "${FIXTURES}/nexus/python-hyphen.json"

  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

# ── script: terraform ─────────────────────────────────────────────────────────

@test "script/terraform: exits 0 when MODIFIED_FILES is empty" {
  cp "${FIXTURES}/convoy-terraform.yaml" convoy.yaml
  export MODIFIED_FILES=""

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "script/terraform: exits 0 when module version is not in Nexus" {
  cp "${FIXTURES}/convoy-terraform.yaml" convoy.yaml
  mkdir -p module-alpha
  cp "${FIXTURES}/terraform-module/convoy.yaml" module-alpha/convoy.yaml
  _mock_curl "${FIXTURES}/nexus/empty.json"
  export MODIFIED_FILES="module-alpha/main.tf module-alpha/variables.tf"

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "script/terraform: exits 1 when module version already exists in Nexus" {
  cp "${FIXTURES}/convoy-terraform.yaml" convoy.yaml
  mkdir -p module-alpha
  cp "${FIXTURES}/terraform-module/convoy.yaml" module-alpha/convoy.yaml
  _mock_curl "${FIXTURES}/nexus/maven2-tf-match.json"
  export MODIFIED_FILES="module-alpha/main.tf"

  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "script/terraform: each module directory is checked only once" {
  cp "${FIXTURES}/convoy-terraform.yaml" convoy.yaml
  mkdir -p module-alpha
  cp "${FIXTURES}/terraform-module/convoy.yaml" module-alpha/convoy.yaml
  # Multiple files from the same dir — Nexus must be queried exactly once.
  # Record the number of curl invocations via a counter file.
  cat > "${MOCK_BIN}/curl" <<EOF
#!/bin/bash
echo 1 >> "${TEST_DIR}/curl_calls"
cat '${FIXTURES}/nexus/empty.json'
EOF
  chmod +x "${MOCK_BIN}/curl"
  export MODIFIED_FILES="module-alpha/main.tf module-alpha/outputs.tf module-alpha/variables.tf"

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  call_count=$(wc -l < "${TEST_DIR}/curl_calls")
  [ "$call_count" -eq 1 ]
}

@test "script/terraform: skips excluded top-level paths (.github, convoy.yaml, etc.)" {
  cp "${FIXTURES}/convoy-terraform.yaml" convoy.yaml
  # No curl stub — if curl were called it would fail (real curl can't reach nexus.test),
  # causing a non-zero exit. A clean exit proves no API call was attempted.
  export MODIFIED_FILES=".github/workflows/ci.yml convoy.yaml README.md .gitignore"

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── script: pagination ────────────────────────────────────────────────────────

@test "script/pagination: exits 0 when version not found across two pages" {
  cp "${FIXTURES}/convoy-java.yaml" convoy.yaml
  _mock_curl_paginated \
    "${FIXTURES}/nexus/paginated-p1-empty.json" \
    "${FIXTURES}/nexus/empty.json"

  run_script "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "script/pagination: exits 1 when version found on second page" {
  cp "${FIXTURES}/convoy-java.yaml" convoy.yaml
  _mock_curl_paginated \
    "${FIXTURES}/nexus/paginated-p1-empty.json" \
    "${FIXTURES}/nexus/maven2-match.json"

  run_script "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}
