# Regsync – Mirror Container Images & Helm Charts to Your Private Registry

A script toolkit to mirror container images and Helm charts from public registries to your private registry.

## 🚀Features

- Mirror Docker/Podman images (e.g., `nginx:latest`)
- Mirror Helm charts (HTTP and OCI)
- Automatic Helm repo management for charts
- Supports dry-run and debug modes
- Flexible input: supports both `nginx:latest` and `nginx --version latest`
- Easy test scripts for real and dry-run cases
- Installation via Makefile
- **Set default registry and paths directly in the script with the `set` command**

## Usage

Run the regsync with command and options:
```bash
# Usage: regsync <command> <name> [options]

# Commands:
#   image <image_name>        Sync a container image.
#   chart <chart_name_or_oci_url> [repo_url]    Sync a Helm chart (OCI if starts with oci://, HTTP otherwise). For HTTP, chart_name can be 'repo/name'.
#   set [--registry <url>] [--image-path <path>] [--chart-path <path>]   Set default registry and paths.

# Options:
#   -v, --version <tag>           Specify the version/tag of the artifact (default: latest).
#   -p, --path <path>             Override the default destination path.
#   -g, --registry <url>          Override the private registry URL.
#   -s, --source-registry <url>   Specify the source registry for the image (e.g., oci.external-secrets.io).
#   -f, --full-image <image>      Specify the full public image reference (auto-detect registry).
#       --debug                   Enable detailed logging to a file in /tmp.
#       --dry-run                 Show what would be done without executing.
#   -h, --help                    Show this help message.
```

Set default registry and paths:
```bash
regsync set --registry <url> --image-path <path> --chart-path <path>
```

> [!NOTE]
> By defaults, destination path is `library` for container images, and `charts` for Helm chart.
> You could override it by using `-p, --path` option

Examples:
```
regsync image nginx:latest
regsync chart hashicorp/vault https://helm.releases.hashicorp.com
regsync chart oci://registry-1.docker.io/bitnamicharts/nginx
```

---
## Requirements

- Shell/Bash
- Docker or Podman
- Helm CLI

## ⚙️Installation

### Quick installation

```bash
curl -fsSL https://github.com/nh4ttruong/regsync/raw/main/install.sh | bash
```

### Manual installation

To install regsync:
```bash
git clone https://github.com/nh4ttruong/regsync.git
cd regsync

# wide system
sudo make install   # Installs regsync to /usr/local/bin (requires root)
sudo make uninstall # Removes regsync from /usr/local/bin

# user only
make install PREFIX=$HOME/.local   # Installs regsync to $HOME/.local/bin
make uninstall PREFIX=$HOME/.local # Removes regsync from $HOME/.local/bin
```

If you install locally, ensure `$HOME/.local/bin` is in your PATH.

## Testing

See [`test/README.md`](test/README) for details on test coverage and usage.

Quick test commands:
```bash
bash test/test_real_cases.sh           # Run real mirroring tests
bash test/test_real_cases.sh --dry-run # Run tests in dry-run mode
```

Test cases include:
- Docker image mirroring (`nginx:latest`)
- Helm chart mirroring (HTTP: `hashicorp/vault`)
- Helm chart mirroring (OCI: `oci://registry-1.docker.io/bitnamicharts/nginx`)

---