#!/usr/bin/env bash
# Install the latest published Flow Steward release on a Docker host: a
# DigitalOcean Droplet, Hostinger VPS, Hetzner Cloud server or any other VPS.
# The release is resolved when this runs, so the script never names a version.
set -euo pipefail
target=${FS_INSTALL_DIR:-flow-steward}
app_repository=https://github.com/Flow-Steward/flow-steward-app.git
releases_api=${FS_RELEASES_API:-https://api.github.com/repos/Flow-Steward/flow-steward-app/releases/latest}

for command_name in git curl docker; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s. See vps/README.md for prerequisites.\n' "$command_name" >&2
    exit 1
  }
done
docker compose version >/dev/null 2>&1 || {
  printf 'Docker Compose v2 (`docker compose`) is required.\n' >&2
  exit 1
}
if [[ -e "$target" ]]; then
  printf '%s already exists. Run ./install.sh inside that checkout, or choose another FS_INSTALL_DIR.\n' "$target" >&2
  exit 1
fi

release_json=$(curl --fail --silent --show-error --location "$releases_api")
tag=$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' <<<"$release_json" \
  | head -n 1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)
if [[ -z "$tag" ]]; then
  printf 'Could not determine the latest published Flow Steward release.\n' >&2
  exit 1
fi

printf 'Installing Flow Steward %s into %s.\n' "$tag" "$target"
# A full clone at the release tag: the installer then uses that release's
# official images instead of building from source.
git -c advice.detachedHead=false clone --branch "$tag" "$app_repository" "$target"
cd "$target"
exec ./install.sh "$@"
