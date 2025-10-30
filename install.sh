#!/bin/bash
set -euo pipefail

# Improved install script for regsync
# - Defaults to latest GitHub release tag
# - Accepts -v|--version to install a specific tag
# - Downloads release asset (regsync or regsync.sh) and installs to a bin dir (default: /usr/local/bin)

REPO_OWNER="nh4ttruong"
REPO_NAME="regsync"
DEFAULT_INSTALL_DIR="/usr/local/bin"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -v, --version <tag>    Specify release tag to install (e.g. 1.0.1 or v1.0.1). If omitted, latest release will be used.
  -d, --dir <path>       Install directory (default: ${DEFAULT_INSTALL_DIR})
  -f, --force            Overwrite destination without prompting
  -h, --help             Show this help message

Examples:
  $0                     # install latest release
  $0 -v 1.2.3            # install release 1.2.3
  $0 --version v1.2.3    # install release v1.2.3 (leading v is accepted)
EOF
}

DOWNLOAD_TAG=""
INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      if [[ -z "${2:-}" || "${2:-}" == -* ]]; then echo "Error: --version requires an argument" >&2; usage; exit 1; fi
      DOWNLOAD_TAG="$2"; shift 2 ;;
    -d|--dir)
      if [[ -z "${2:-}" || "${2:-}" == -* ]]; then echo "Error: --dir requires an argument" >&2; usage; exit 1; fi
      INSTALL_DIR="$2"; shift 2 ;;
    -f|--force)
      FORCE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Determine tag: if DOWNLOAD_TAG empty, query GitHub API for latest
if [[ -z "${DOWNLOAD_TAG}" ]]; then
  echo "Fetching latest release tag from GitHub for ${REPO_OWNER}/${REPO_NAME}..."
  TAG_JSON=$(curl -sSf "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest") || { echo "Failed to query GitHub API" >&2; exit 1; }
  DOWNLOAD_TAG=$(echo "$TAG_JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n1)
  if [[ -z "$DOWNLOAD_TAG" ]]; then
    echo "Could not determine latest tag from GitHub API response." >&2
    exit 1
  fi
  echo "Latest tag: ${DOWNLOAD_TAG}"
else
  echo "Using requested tag: ${DOWNLOAD_TAG}"
fi

# Normalize tag for download URL: GitHub releases often include 'v' in tag name; use as-is for URL
TAG_FOR_URL="$DOWNLOAD_TAG"

ASSET_NAMES=("regsync" "regsync.sh")

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

download_asset() {
  local tag="$1"
  for name in "${ASSET_NAMES[@]}"; do
    url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${tag}/${name}"
    echo "Attempting to download asset: ${name} from ${url}"
    if curl -fSL -o "${TMPDIR}/${name}" "${url}"; then
      echo "Downloaded ${name}"
      echo "${TMPDIR}/${name}"
      return 0
    else
      echo "Asset ${name} not found at ${url} (trying next)" >&2
    fi
  done
  return 1
}

ASSET_PATH=""
if ASSET_PATH=$(download_asset "${TAG_FOR_URL}"); then
  echo "Asset downloaded to ${ASSET_PATH}"
else
  echo "Failed to download any release asset for tag ${TAG_FOR_URL}" >&2
  exit 1
fi

# Make executable
chmod +x "$ASSET_PATH"

DEST_PATH="${INSTALL_DIR%/}/regsync"

if [[ -e "$DEST_PATH" && "$FORCE" -ne 1 ]]; then
  echo "Destination $DEST_PATH already exists." 
  read -p "Overwrite? [y/N]: " yn
  case "$yn" in
    [Yy]*) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

echo "Installing to ${DEST_PATH} (may require sudo)"
if mv "$ASSET_PATH" "$DEST_PATH" 2>/dev/null; then
  echo "Installed to ${DEST_PATH}"
else
  echo "Elevated install: moving with sudo"
  sudo mv "$ASSET_PATH" "$DEST_PATH"
fi

sudo chmod 0755 "$DEST_PATH" 2>/dev/null || chmod 0755 "$DEST_PATH"

echo "Installation complete. Run 'regsync --help' to get started."

exit 0