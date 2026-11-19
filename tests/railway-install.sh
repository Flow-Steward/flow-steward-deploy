#!/usr/bin/env bash
# Bounded control-flow tests. Live provider acceptance remains mandatory.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
installer="$script_dir/../railway/install.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
cat > "$fixture/bin/railway" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FIXTURE/commands"
case "$1" in
  whoami)
    [[ -f "$FIXTURE/authenticated" ]] || exit 1
    printf '%s\n' '{"workspaces":[{"id":"workspace-test","name":"Personal workspace"}]}' ;;
  login) touch "$FIXTURE/authenticated" ;;
  init) touch "$FIXTURE/linked" ;;
  status)
    [[ -f "$FIXTURE/linked" ]] || exit 1
    printf '%s\n' '{"id":"project-test","name":"Flow Steward","environments":{"edges":[{"node":{"id":"env-test","name":"production"}}]},"services":{"edges":[{"node":{"id":"existing","name":"existing"}}]}}' ;;
  *) printf 'Unexpected mutation: %s\n' "$*" >&2; exit 9 ;;
esac
MOCK
chmod 755 "$fixture/bin/railway"
export FIXTURE="$fixture"
export PATH="$fixture/bin:$PATH"

# New user runs only the installer; it signs in and creates the project itself.
if printf '\n' | bash "$installer" > "$fixture/output" 2>&1; then
  printf 'Expected the populated-project safety guard to refuse deployment.\n' >&2
  exit 1
fi
grep -qx 'login' "$fixture/commands"
grep -qx 'init --name flow-steward --workspace workspace-test --json' "$fixture/commands"
grep -q 'already contains services' "$fixture/output"
if grep -Eq '^(add|volume|variable|service) ' "$fixture/commands"; then exit 1; fi

# A linked populated project must never create or modify any cloud resources.
: > "$fixture/commands"
if bash "$installer" < /dev/null > "$fixture/output" 2>&1; then exit 1; fi
grep -q 'already contains services' "$fixture/output"
if grep -Eq '^(init|add|volume|variable|service) ' "$fixture/commands"; then exit 1; fi
printf 'Railway onboarding and existing-project protection passed.\n'
