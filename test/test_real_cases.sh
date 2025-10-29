#!/bin/bash
# test_real_cases.sh
# Run real mirroring tests for image and chart (default real, --dry-run for dry-run)

set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR_SCRIPT="$SCRIPT_DIR/../regsync.sh"
DRY_RUN=""

for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
  fi
  if [[ "$arg" == "--debug" ]]; then
    DEBUG="--debug"
  fi
  # Pass through any other args
  EXTRA_ARGS+=" $arg"
  shift
done

run_test() {
  local desc="$1"
  local cmd="$2"
  echo -e "\n===== $desc ====="
  eval "$cmd"
}

# Test 1: Mirror nginx image (real or dry-run)

# Test 2: Mirror vault chart (http chart)

# Test 3: Mirror OCI chart (bitnami/nginx)
run_test "Image: nginx:latest" "bash $MIRROR_SCRIPT image nginx:latest $DRY_RUN $DEBUG"

# Test 2: Mirror vault chart (http chart)
run_test "Chart: hashicorp/vault from https://helm.releases.hashicorp.com" "bash $MIRROR_SCRIPT chart hashicorp/vault https://helm.releases.hashicorp.com $DRY_RUN $DEBUG"

# Test 3: Mirror OCI chart (bitnami/nginx)
run_test "Chart: oci://registry-1.docker.io/bitnamicharts/nginx (OCI)" "bash $MIRROR_SCRIPT chart oci://registry-1.docker.io/bitnamicharts/nginx $DRY_RUN $DEBUG"

