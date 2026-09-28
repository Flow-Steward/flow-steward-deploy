#!/usr/bin/env bash
# Exercise the installer, replacing only the external, billable Fly boundary.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/config" "$fixture/private"
cp "$root"/fly/*.toml "$fixture/config/"
cp "$root/fly/install.sh" "$fixture/config/install.sh"
cat > "$fixture/bin/fly" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURE/commands"
case "$1 $2" in
  'auth whoami') exit 0 ;;
  'orgs list') printf '{"personal":"Test organization"}\n' ;;
  'apps list') if [[ "$CASE" = existing ]]; then printf '[{"Name":"test-fs-pg"}]\n'; else printf '[]\n'; fi ;;
  'config validate') exit 0 ;;
  'apps create'|'volumes create'|'ips allocate-v6'|'ips allocate-v4') exit 0 ;;
  'secrets import') cat >/dev/null ;;
  'ssh console')
    if [[ "$*" = *pg_isready* && "$CASE" = failed-pg ]]; then exit 1; fi
    exit 0 ;;
  *)
    if [[ "$1" = deploy ]]; then
      [[ "$CASE" != failed-app || "$*" != *compact.toml* ]] || exit 1
      exit 0
    fi
    if [[ "$1" = logs ]]; then
      [[ "$*" != *--no-tail* ]] || exit 0
      printf '%s\n' "$$" > "$FIXTURE/reader-pid"
      trap 'exit 0' TERM
      printf '{\n  "message": "https://test-fs-compact.fly.dev/bootstrap#setup-token=test-only"\n}\n'
      while :; do sleep 1; done
    fi
    printf 'Unexpected Fly command: %s\n' "$*" >&2; exit 9 ;;
esac
MOCK
cat > "$fixture/bin/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod 755 "$fixture/bin/"*
export FIXTURE="$fixture" PATH="$fixture/bin:$PATH"
export TMPDIR="$fixture/private"
: > "$fixture/commands"


# A collision must prevent every cloud mutation, even in the other two apps.
export CASE=existing
if printf 'test-fs\n\n' | bash "$fixture/config/install.sh" > "$fixture/output" 2>&1; then
  printf 'Existing app was not refused\n' >&2; exit 1
fi
if grep -Eq '^(apps create|volumes|secrets|ips|deploy)' "$fixture/commands"; then
  printf 'Installer modified resources after name collision\n' >&2; exit 1
fi

# A failed PostgreSQL readiness probe must not deploy RabbitMQ or Compact.
export CASE=failed-pg
: > "$fixture/commands"
if printf 'test-fs\n\n' | bash "$fixture/config/install.sh" > "$fixture/output" 2>&1; then
  printf 'Failed dependency was ignored\n' >&2; exit 1
fi
[[ $(grep -c '^deploy ' "$fixture/commands") -eq 1 ]]
grep -q 'fly apps destroy test-fs-pg' "$fixture/output"
rm -rf "$fixture/config/generated"

# A failure after subscription must stop the log reader and remove captures.
export CASE=failed-app
: > "$fixture/commands"
if printf 'test-fs\n\n' | bash "$fixture/config/install.sh" > "$fixture/output" 2>&1; then exit 1; fi
if [[ -f "$fixture/reader-pid" ]]; then
  if kill -0 "$(cat "$fixture/reader-pid")" 2>/dev/null; then
    printf 'Failed install left its log reader alive\n' >&2; exit 1
  fi
fi
[[ -z $(find "$fixture/private" -type f -print -quit) ]]
rm -rf "$fixture/config/generated"

# Fresh installation succeeds without passwords or manual environment inputs.
export CASE=success
: > "$fixture/commands"
printf 'test-fs\n\n' | bash "$fixture/config/install.sh" > "$fixture/output" 2>&1
pg_probe=$(grep -n 'pg_isready' "$fixture/commands" | cut -d: -f1)
rabbit_deploy=$(grep -n '^deploy .*rabbitmq.toml' "$fixture/commands" | cut -d: -f1)
rabbit_probe=$(grep -n 'rabbitmq-diagnostics' "$fixture/commands" | cut -d: -f1)
app_deploy=$(grep -n '^deploy .*compact.toml' "$fixture/commands" | cut -d: -f1)
(( pg_probe < rabbit_deploy && rabbit_probe < app_deploy ))
grep -q 'https://test-fs-compact.fly.dev/bootstrap#setup-token=test-only' "$fixture/output"
if kill -0 "$(cat "$fixture/reader-pid")" 2>/dev/null; then
  printf 'Successful install left its log reader alive\n' >&2; exit 1
fi
[[ -z $(find "$fixture/private" -type f -print -quit) ]]
grep -q "POSTGRES_HOST = 'test-fs-pg.internal'" "$fixture/config/generated/test-fs/compact.toml"
if grep -q 'PASSWORD\|RABBITMQ_PASS' "$fixture/config/generated/test-fs/"*.toml; then
  printf 'Generated configs contain credentials\n' >&2; exit 1
fi
printf 'Fly installer collision protection, dependency ordering and fresh setup passed.\n'
