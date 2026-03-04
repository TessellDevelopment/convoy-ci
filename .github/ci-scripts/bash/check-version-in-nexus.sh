#!/bin/bash

# check-version-in-nexus.sh
# Reads convoy.yaml from the current working directory, resolves artifact
# coordinates, and verifies the version does not already exist in Nexus.
# Exits with non-zero status if a matching version is found.
#
# Required environment variables:
#   NEXUS_URL           - Nexus search API base URL ending with "?repository"
#   NEXUS_USERNAME      - Nexus credentials
#   NEXUS_PASSWORD      - Nexus credentials
#   NEXUS_PUSH_REPOS_M2 - Maven2 repository name (used for terraform, java, and all others)
#   NEXUS_PUSH_REPOS_PY - Python repository name
#
# Optional environment variables:
#   MODIFIED_FILES      - Space-separated list of modified files (required for terraform)

set -euo pipefail

CONVOY_YAML="./convoy.yaml"

# ---------------------------------------------------------------------------
# check_page <response_json> <exporter> <repo_type>
#   Prints the number of items in a Nexus search response page that exactly
#   match the artifact name.  Uses jq field comparison to avoid the false
#   positives caused by grep pattern matching on the raw response body.
# ---------------------------------------------------------------------------
check_page() {
  local response="$1"
  local exporter="$2"
  local repo_type="$3"

  case "$repo_type" in
    python)
      # PyPI repo: normalise both sides per PEP 508 (hyphens, underscores, and
      # dots are all equivalent; comparison is case-insensitive) so that e.g.
      # "my-pkg" and "my_pkg" are treated as the same package name.
      echo "$response" | jq -r --arg name "$exporter" \
        '[.items[] | select(
            (.name | gsub("[-_.]"; "_") | ascii_downcase)
            == ($name | gsub("[-_.]"; "_") | ascii_downcase)
         )] | length'
      ;;
    *)
      # Maven2 repo (terraform, java, and all other types):
      # artifact IDs are case-sensitive; use exact equality.
      echo "$response" | jq -r --arg name "$exporter" \
        '[.items[] | select(.name == $name)] | length'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# check_version_in_nexus <nexus_repo> <exporter> <version> <repo_type>
#   Queries Nexus (with pagination) for the given artifact/version.
#   Exits 1 immediately if a match is found.
# ---------------------------------------------------------------------------
check_version_in_nexus() {
  local nexus_repo="$1"
  local exporter="$2"
  local version="$3"
  local repo_type="$4"

  local api_url="${NEXUS_URL}=${nexus_repo}&version=${version}"
  echo "Checking Nexus: artifact='${exporter}' version='${version}' repo='${nexus_repo}' type='${repo_type}'"

  local response
  response=$(curl -sf -u "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" -X GET "${api_url}")

  local count
  count=$(check_page "$response" "$exporter" "$repo_type")
  if [ "$count" -gt 0 ]; then
    echo "FAIL: Version ${version} of ${exporter} already exists in Nexus. Update the version before merging."
    exit 1
  fi

  while [ "$(echo "$response" | jq -r '.continuationToken')" != "null" ]; do
    local token
    token=$(echo "$response" | jq -r '.continuationToken')
    response=$(curl -sf -u "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" -X GET "${api_url}&continuationToken=${token}")

    count=$(check_page "$response" "$exporter" "$repo_type")
    if [ "$count" -gt 0 ]; then
      echo "FAIL: Version ${version} of ${exporter} already exists in Nexus. Update the version before merging."
      exit 1
    fi
  done

  echo "PASS: Version ${version} of ${exporter} not found in Nexus."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ ! -f "$CONVOY_YAML" ]; then
  echo "convoy.yaml not found, skipping version check."
  exit 0
fi

language=$(yq '.language // ""' "$CONVOY_YAML")
app_group=$(yq '.appGroup // "tessell"' "$CONVOY_YAML")

case "$language" in

  terraform)
    if [ -z "${MODIFIED_FILES:-}" ]; then
      echo "No modified files provided for terraform, skipping version check."
      exit 0
    fi

    # Collect unique top-level directories from the changed-files list.
    # Space-padded string used for whole-word deduplication (bash 3 compatible).
    seen_dirs=" "
    exclude=".github convoy.yaml .gitignore README.md"

    for file in $MODIFIED_FILES; do
      dir="${file%%/*}"

      # Skip already-processed directories.
      case "$seen_dirs" in
        *" $dir "*) continue ;;
      esac
      seen_dirs="$seen_dirs$dir "

      # Skip excluded entries.
      case " $exclude " in
        *" $dir "*) continue ;;
      esac

      tf_convoy="${dir}/convoy.yaml"
      if [ ! -f "$tf_convoy" ]; then
        echo "No convoy.yaml found in '${dir}', skipping."
        continue
      fi

      tf_exporter=$(yq '.generates.artifacts[0].name' "$tf_convoy")
      tf_version=$(yq '.version' "$tf_convoy")

      if [ "$app_group" != "tessell" ]; then
        tf_exporter="${app_group}-${tf_exporter}"
      fi

      check_version_in_nexus "$NEXUS_PUSH_REPOS_M2" "$tf_exporter" "$tf_version" "maven2"
    done
    ;;

  python)
    version=$(yq '.version // ""' "$CONVOY_YAML")
    exporter=$(yq '.generates.artifacts[0].name // ""' "$CONVOY_YAML")
    # Normalise Python package name: replace hyphens with underscores.
    exporter="${exporter//-/_}"

    if [ -z "$version" ] || [ -z "$exporter" ]; then
      echo "Required fields (version, generates.artifacts[0].name) missing in convoy.yaml, skipping."
      exit 0
    fi

    check_version_in_nexus "$NEXUS_PUSH_REPOS_PY" "$exporter" "$version" "python"
    ;;

  *)
    # Java and all other language types use the Maven2 repository.
    version=$(yq '.version // ""' "$CONVOY_YAML")
    exporter=$(yq '.generates.artifacts[0].name // ""' "$CONVOY_YAML")

    if [ -z "$version" ] || [ -z "$exporter" ]; then
      echo "Required fields (version, generates.artifacts[0].name) missing in convoy.yaml, skipping."
      exit 0
    fi

    check_version_in_nexus "$NEXUS_PUSH_REPOS_M2" "$exporter" "$version" "maven2"
    ;;

esac
