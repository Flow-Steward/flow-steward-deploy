#!/usr/bin/env bash
# Fresh, single-instance installation using the shared public images.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fly_command=$(command -v fly || command -v flyctl || true)
if [[ -z "$fly_command" ]]; then
  printf 'Install the official Fly CLI first: https://fly.io/docs/flyctl/install/\n' >&2
  exit 1
fi
for dependency in jq openssl curl; do
  command -v "$dependency" >/dev/null || {
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  }
done
if ! "$fly_command" auth whoami >/dev/null 2>&1; then
  "$fly_command" auth login
fi
organizations=$("$fly_command" orgs list --json)
organization_count=$(jq 'length' <<<"$organizations")
if (( organization_count == 0 )); then
  printf 'No Fly organization is available. Complete account setup first.\n' >&2
  exit 1
fi
organization_index=1
if (( organization_count > 1 )); then
  printf 'Choose the organization that will be billed:\n'
  jq -r 'to_entries | sort_by(.key) | to_entries[] | "\(.key + 1). \(.value.key): \(.value.value)"' <<<"$organizations"
  read -r -p 'Organization number [1]: ' selection || true
  organization_index=${selection:-1}
  if [[ ! "$organization_index" =~ ^[0-9]+$ ]] ||
    (( organization_index < 1 || organization_index > organization_count )); then
    printf 'Choose one of the listed organization numbers.\n' >&2
    exit 1
  fi
fi
organization=$(jq -r --argjson index "$((organization_index - 1))" 'keys | .[$index]' <<<"$organizations")
default_prefix="flow-steward-$(openssl rand -hex 3)"
read -r -p "Installation name [$default_prefix]: " selection || true
prefix=${selection:-$default_prefix}
if [[ ! "$prefix" =~ ^[a-z][a-z0-9-]{1,39}$ || "$prefix" = *- ]]; then
  printf 'Use 2–40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter/digit.\n' >&2
  exit 1
fi
read -r -p 'Region [fra]: ' selection || true
region=${selection:-fra}
if [[ ! "$region" =~ ^[a-z]{3}$ ]]; then
  printf 'Use a three-letter Fly region code.\n' >&2
  exit 1
fi
existing_apps=$("$fly_command" apps list --json)
for role in pg rabbit compact; do
  if jq -e --arg name "$prefix-$role" 'any(.[]; (.Name // .name) == $name)' <<<"$existing_apps" >/dev/null; then
    printf 'App %s already exists. This fresh installer will not modify it.\n' "$prefix-$role" >&2
    exit 1
  fi
done
config_dir="$script_dir/generated/$prefix"
if [[ -e "$config_dir" ]]; then
  printf 'Configuration directory already exists: %s. Use a new installation name.\n' "$config_dir" >&2
  exit 1
fi
mkdir -p "$config_dir"
for role in postgres rabbitmq compact; do
  sed -e "s/your-fs-demo/$prefix/g" -e "s/primary_region = 'fra'/primary_region = '$region'/" \
    "$script_dir/$role.toml" > "$config_dir/$role.toml"
  "$fly_command" config validate --strict -c "$config_dir/$role.toml"
done
created_apps=()
created_count=0
startup_log=
log_reader=
finish() {
  code=$?
  unset postgres_password rabbitmq_password
  if [[ -n "$log_reader" ]]; then
    kill "$log_reader" 2>/dev/null || true
    wait "$log_reader" 2>/dev/null || true
  fi
  if [[ -n "$startup_log" ]]; then rm -f "$startup_log" "$startup_log.errors"; fi
  if (( code != 0 && created_count > 0 )); then
    printf '\nInstallation did not finish. Created resources remain billable. Inspect their logs or delete this disposable installation with:\n' >&2
    for app in "${created_apps[@]}"; do printf '  fly apps destroy %s\n' "$app" >&2; done
    printf 'Saved configurations: %s\n' "$config_dir" >&2
  fi
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Creating three apps in %s/%s. Compute and persistent storage incur Fly charges.\n' "$organization" "$region"
for role in pg rabbit compact; do
  "$fly_command" apps create "$prefix-$role" --org "$organization" --json --yes >/dev/null
  created_apps+=("$prefix-$role")
  created_count=$((created_count + 1))
done
"$fly_command" volumes create postgres_data -a "$prefix-pg" --region "$region" --size 10 --yes >/dev/null
"$fly_command" volumes create rabbitmq_data -a "$prefix-rabbit" --region "$region" --size 1 --yes >/dev/null
"$fly_command" volumes create compact_data -a "$prefix-compact" --region "$region" --size 10 --yes >/dev/null
postgres_password=$(openssl rand -hex 32)
rabbitmq_password=$(openssl rand -hex 32)
printf 'POSTGRES_PASSWORD=%s\n' "$postgres_password" | "$fly_command" secrets import -a "$prefix-pg"
printf 'RABBITMQ_DEFAULT_PASS=%s\n' "$rabbitmq_password" | "$fly_command" secrets import -a "$prefix-rabbit"
printf 'POSTGRES_PASSWORD=%s\nRABBITMQ_PASS=%s\n' "$postgres_password" "$rabbitmq_password" | "$fly_command" secrets import -a "$prefix-compact"
unset postgres_password rabbitmq_password
"$fly_command" ips allocate-v6 -a "$prefix-compact"
"$fly_command" ips allocate-v4 --shared -a "$prefix-compact"

# Dependencies have no public listeners; only Compact receives public IPs.
"$fly_command" deploy -c "$config_dir/postgres.toml" --ha=false --yes --wait-timeout 10m
"$fly_command" ssh console -a "$prefix-pg" -C 'pg_isready -U flow_steward -d flow_steward'
"$fly_command" deploy -c "$config_dir/rabbitmq.toml" --ha=false --yes --wait-timeout 10m
"$fly_command" ssh console -a "$prefix-rabbit" -C 'rabbitmq-diagnostics -q ping'
# Fly's recent-log buffer can lose the setup line during startup health checks.
# Subscribe before the first Compact Machine starts; keep the capture private
# and delete it on both success and failure.
umask 077
startup_log=$(mktemp)
chmod 600 "$startup_log"
"$fly_command" logs -a "$prefix-compact" --json > "$startup_log" 2> "$startup_log.errors" &
log_reader=$!
"$fly_command" deploy -c "$config_dir/compact.toml" --ha=false --yes --wait-timeout 10m
public_url="https://$prefix-compact.fly.dev"
ready=0
for attempt in $(seq 1 120); do
  if curl --fail --silent --show-error --max-time 10 "$public_url/health/ready" >/dev/null 2>&1; then
    ready=1
    break
  fi
  printf 'Waiting for public readiness (%s/120)...\n' "$attempt"
  sleep 5
done
if (( ready == 0 )); then
  printf 'Public readiness did not succeed. Inspect: fly logs -a %s-compact\n' "$prefix" >&2
  exit 1
fi
"$fly_command" ssh console -a "$prefix-compact" -C 'flow-steward status'
printf '\nFlow Steward is ready: %s\nSaved configurations: %s\n' "$public_url" "$config_dir"
# Stop the reader before parsing. Fly emits pretty JSON objects, not one JSON
# value per line; jq reads the stream of objects. An interrupted trailing
# record may be incomplete, while earlier complete setup records remain valid.
kill "$log_reader" 2>/dev/null || true
wait "$log_reader" 2>/dev/null || true
log_reader=
setup_url=$(jq -r '.message // empty' "$startup_log" 2>/dev/null | grep -oE 'https://[^[:space:]"<>]+/bootstrap[^[:space:]"<>]*' | tail -n 1 || true)
if [[ -n "$setup_url" ]]; then
  printf 'Private first-administrator link (expires after 15 minutes; do not share):\n%s\n' "$setup_url"
else
  printf 'Create the first administrator interactively:\n  fly ssh console -a %s-compact --pty -C '\''flow-steward users create --role admin --plain'\''\n' "$prefix"
fi
printf 'Administration:\n  fly ssh console -a %s-compact -C '\''flow-steward --help'\''\n' "$prefix"
