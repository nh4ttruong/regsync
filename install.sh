#!/bin/bash
# install.sh - Automated installer for regsync and dependencies
set -e

REPO_URL="https://raw.githubusercontent.com/nh4ttruong/regsync/main/install.sh"
INSTALL_PATH="/usr/local/bin"
SCRIPT_NAME="regsync.sh"
BINARY_NAME="regsync"
MAKEFILE_NAME="Makefile"

# Download regsync.sh and Makefile
curl -fsSL "$REPO_URL/$SCRIPT_NAME" -o "$SCRIPT_NAME"
curl -fsSL "$REPO_URL/$MAKEFILE_NAME" -o "$MAKEFILE_NAME"

# Check for required tools
missing=0
if ! command -v bash >/dev/null 2>&1; then
  echo "Error: Bash is not installed. See https://www.gnu.org/software/bash/"
  missing=1
fi
if ! command -v helm >/dev/null 2>&1; then
  echo "Error: Helm is not installed. See https://helm.sh/docs/intro/install/"
  missing=1
fi
if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
  echo "Error: Docker or Podman is not installed."
  echo "Docker: https://docs.docker.com/get-docker/"
  echo "Podman: https://podman.io/getting-started/installation"
  missing=1
fi
if [ "$missing" -eq 1 ]; then
  echo "Please install the missing tools and re-run this script."
  exit 1
fi

# Install regsync
if [ "$EUID" -ne 0 ]; then
  echo "Installing to $HOME/.local/bin (user mode)"
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$SCRIPT_NAME" "$HOME/.local/bin/$BINARY_NAME"
  echo "regsync installed to $HOME/.local/bin/$BINARY_NAME"
  echo "Add export PATH=\"$HOME/.local/bin:$PATH\" to your shell profile if needed."
else
  echo "Installing to $INSTALL_PATH (system mode)"
  install -m 0755 "$SCRIPT_NAME" "$INSTALL_PATH/$BINARY_NAME"
  echo "regsync installed to $INSTALL_PATH/$BINARY_NAME"
fi

# Clean up
rm -f "$SCRIPT_NAME"

# Success message
cat <<EOF

Installation complete!
Usage:
  regsync image nginx:latest
  regsync chart hashicorp/vault https://helm.releases.hashicorp.com
  regsync chart oci://registry-1.docker.io/bitnamicharts/nginx

For more info, see README.md or run: make help
EOF
