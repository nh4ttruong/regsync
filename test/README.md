# Test Scripts

This directory contains test scripts for validating the functionality of the regsync toolkit.

## Scripts
- `test_real_cases.sh`: Runs real mirroring tests for images and charts. Add `--dry-run` to simulate actions without making changes.

## Usage
```bash
bash test_real_cases.sh           # Run real mirroring tests
bash test_real_cases.sh --dry-run # Run tests in dry-run mode
```

## Test Cases Covered
- Mirror Docker image: `nginx:latest`
- Mirror Helm chart (HTTP): `hashicorp/vault` from `https://helm.releases.hashicorp.com`
- Mirror Helm chart (OCI): `oci://registry-1.docker.io/bitnamicharts/nginx`

Each case checks:
- Pull from public source
- Push to private registry
- Handles both real and dry-run execution

Tests cover:
- Docker image mirroring (e.g., nginx:latest)
- Helm chart mirroring (HTTP and OCI)