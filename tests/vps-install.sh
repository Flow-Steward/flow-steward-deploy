#!/usr/bin/env bash
# Exercise the VPS launcher, replacing only GitHub, Git and Docker.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/work"
cat > "$fixture/bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '{\n  "url": "x",\n  "tag_name": "%s",\n  "name": "release"\n}\n' "$RELEASE_TAG"
MOCK
cat > "$fixture/bin/docker" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" = 'compose version' ]]
MOCK
cat > "$fixture/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FIXTURE/commands"
target=${*: -1}
mkdir -p "$target"
printf '#!/usr/bin/env bash\nprintf "install %%s\\n" "$*" >> "$FIXTURE/commands"\n' > "$target/install.sh"
chmod 755 "$target/install.sh"
MOCK
chmod 755 "$fixture"/bin/*
export FIXTURE="$fixture" PATH="$fixture/bin:$PATH"
cd "$fixture/work"

# The latest release tag is resolved at run time and installed from its tag.
RELEASE_TAG=v7.8.9 bash "$root/vps/install.sh" --plain > "$fixture/output"
grep -qx -- '-c advice.detachedHead=false clone --branch v7.8.9 https://github.com/Flow-Steward/flow-steward-app.git flow-steward' "$fixture/commands"
grep -qx 'install --plain' "$fixture/commands"

# An existing directory is never reused.
: > "$fixture/commands"
if RELEASE_TAG=v7.8.9 bash "$root/vps/install.sh" > "$fixture/output" 2>&1; then exit 1; fi
grep -q 'already exists' "$fixture/output"
[[ ! -s "$fixture/commands" ]]

# A response without a stable release tag stops before cloning.
if RELEASE_TAG=nightly FS_INSTALL_DIR=other bash "$root/vps/install.sh" > "$fixture/output" 2>&1; then exit 1; fi
grep -q 'Could not determine' "$fixture/output"
[[ ! -e other ]]
printf 'VPS launcher resolves the latest release and refuses existing checkouts.\n'
