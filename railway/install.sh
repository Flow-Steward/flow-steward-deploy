#!/usr/bin/env bash
# Guided fresh Railway project with the release images pinned in release.env.
# Railway's single-service railway.json cannot order three services. This script
# leaves every service without an image until its volume and variables exist.
set -euo pipefail

environment_name=production
# The images of the release this repository pins; sync-release keeps it current.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../release.env
source "$script_dir/../release.env"
flow_steward_release=$FLOW_STEWARD_RELEASE
postgres_image=$POSTGRES_IMAGE
rabbitmq_image=$RABBITMQ_IMAGE
compact_image=$COMPACT_IMAGE

for command_name in railway jq openssl curl; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

if ! account_json=$(railway whoami --json 2>/dev/null); then
  printf 'Sign in to Railway in the browser opened by the installer.\n'
  railway login
  account_json=$(railway whoami --json)
fi

project_json=$(railway status --json 2>/dev/null || true)
if [[ -z "$project_json" ]]; then
  workspace_count=$(jq '.workspaces | length' <<<"$account_json")
  if [[ "$workspace_count" -eq 0 ]]; then
    printf 'Your Railway account has no workspace. Complete account setup in Railway first.\n' >&2
    exit 1
  fi
  workspace_index=1
  if [[ "$workspace_count" -gt 1 ]]; then
    printf 'Choose the workspace that should be billed for this installation:\n'
    jq -r '.workspaces | to_entries[] | "\(.key + 1). \(.value.name)"' <<<"$account_json"
    read -r -p 'Workspace number [1]: ' workspace_selection || true
    workspace_index=${workspace_selection:-1}
    if [[ ! "$workspace_index" =~ ^[0-9]+$ ]] ||
      (( workspace_index < 1 || workspace_index > workspace_count )); then
      printf 'Choose one of the listed workspace numbers.\n' >&2
      exit 1
    fi
  fi
  workspace_id=$(jq -r --argjson index "$((workspace_index - 1))" \
    '.workspaces[$index].id' <<<"$account_json")
  read -r -p 'New project name [flow-steward]: ' project_selection || true
  new_project_name=${project_selection:-flow-steward}
  printf 'Creating Railway project %s. Its services and volumes incur Railway charges.\n' \
    "$new_project_name"
  railway init --name "$new_project_name" --workspace "$workspace_id" --json >/dev/null
  project_json=$(railway status --json)
fi
project_id=$(jq -r '.id // empty' <<<"$project_json")
project_name=$(jq -r '.name // empty' <<<"$project_json")
environment_id=$(jq -r --arg name "$environment_name" \
  '.environments.edges[] | select(.node.name == $name) | .node.id' <<<"$project_json")
if [[ -z "$project_id" || -z "$environment_id" ]]; then
  printf 'Railway did not return a project with a production environment. Inspect the project in Railway.\n' >&2
  exit 1
fi
if [[ $(jq '.services.edges | length' <<<"$project_json") -ne 0 ]]; then
  printf 'The linked project already contains services. This fresh-install example will not modify it.\n' >&2
  exit 1
fi

printf 'Installing Flow Steward %s.\n' "$flow_steward_release"
printf 'Creating empty services and persistent volumes in %s (%s).\n' "$project_name" "$project_id"
for service_name in postgres rabbitmq compact; do
  railway add --service "$service_name" --json >/dev/null
done

for service_name in postgres rabbitmq compact; do
  railway link --project "$project_id" --environment "$environment_name" \
    --service "$service_name" --json >/dev/null
  case "$service_name" in
    postgres) mount_path=/var/lib/postgresql/data ;;
    rabbitmq) mount_path=/var/lib/rabbitmq ;;
    compact) mount_path=/data ;;
  esac
  railway volume add --mount-path "$mount_path" --json >/dev/null
done

postgres_password=$(openssl rand -hex 24)
rabbitmq_password=$(openssl rand -hex 24)
railway variable set PGDATA=/var/lib/postgresql/data/pgdata \
  POSTGRES_DB=flow_steward POSTGRES_USER=flow_steward \
  --service postgres --project "$project_id" --environment "$environment_name" \
  --skip-deploys --json >/dev/null
printf '%s' "$postgres_password" | railway variable set POSTGRES_PASSWORD --stdin \
  --service postgres --project "$project_id" --environment "$environment_name" \
  --skip-deploys --json >/dev/null
railway variable set RABBITMQ_DEFAULT_USER=flow_steward RABBITMQ_DEFAULT_VHOST=flow \
  --service rabbitmq --project "$project_id" --environment "$environment_name" \
  --skip-deploys --json >/dev/null
printf '%s' "$rabbitmq_password" | railway variable set RABBITMQ_DEFAULT_PASS --stdin \
  --service rabbitmq --project "$project_id" --environment "$environment_name" \
  --skip-deploys --json >/dev/null
unset postgres_password rabbitmq_password

wait_for_service() {
  local service_name=$1 expected_log=$2 deployment_id status output deploy_logs
  local deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    output=$(railway deployment list --service "$service_name" --project "$project_id" \
      --environment "$environment_name" --json)
    deployment_id=$(jq -r '.[0].id // empty' <<<"$output")
    status=$(jq -r '.[0].status // empty' <<<"$output")
    case "$status" in
      FAILED|CRASHED|REMOVED)
        printf '%s deployment %s ended with %s. Inspect Railway logs.\n' \
          "$service_name" "$deployment_id" "$status" >&2
        return 1 ;;
      SUCCESS)
        # Read the logs completely first: `grep -q` would close the pipe early,
        # the CLI then aborts, and pipefail turns a match into a retry.
        deploy_logs=$(railway logs "$deployment_id" --service "$service_name" \
          --project "$project_id" --environment "$environment_name" \
          --lines 500 2>/dev/null || true)
        if grep -Fq "$expected_log" <<<"$deploy_logs"; then
          printf '%s is ready (deployment %s).\n' "$service_name" "$deployment_id"
          return 0
        fi ;;
    esac
    sleep 5
  done
  printf 'Timed out waiting for %s. Inspect Railway logs.\n' "$service_name" >&2
  return 1
}

printf 'Starting PostgreSQL first.\n'
railway service source connect --image "$postgres_image" --service postgres \
  --project "$project_id" --environment "$environment_name" --json >/dev/null
wait_for_service postgres 'database system is ready to accept connections'

printf 'Starting RabbitMQ second.\n'
railway service source connect --image "$rabbitmq_image" --service rabbitmq \
  --project "$project_id" --environment "$environment_name" --json >/dev/null
wait_for_service rabbitmq 'Server startup complete'

railway domain --port 8080 --service compact --project "$project_id" \
  --environment "$environment_name" --json >/dev/null
domain=$(railway domain list --service compact --project "$project_id" \
  --environment "$environment_name" --json | jq -r '.domains[] | select(.type == "service") | .domain' | head -n 1)
if [[ -z "$domain" ]]; then
  printf 'Railway did not return a public Compact domain.\n' >&2
  exit 1
fi

# Plaintext AMQP is allowed only to this one host on Railway's private network,
# which Railway encrypts with WireGuard and isolates per environment (ADR 0064).
railway variable set \
  'FS_DB_DSN=postgresql://${{postgres.POSTGRES_USER}}:${{postgres.POSTGRES_PASSWORD}}@postgres.railway.internal:5432/${{postgres.POSTGRES_DB}}' \
  'RABBITMQ_URL=amqp://${{rabbitmq.RABBITMQ_DEFAULT_USER}}:${{rabbitmq.RABBITMQ_DEFAULT_PASS}}@rabbitmq.railway.internal:5672/flow' \
  'POSTGRES_DB=${{postgres.POSTGRES_DB}}' \
  'POSTGRES_USER=${{postgres.POSTGRES_USER}}' \
  'POSTGRES_PASSWORD=${{postgres.POSTGRES_PASSWORD}}' \
  POSTGRES_HOST=postgres.railway.internal \
  RABBITMQ_HOST=rabbitmq.railway.internal \
  FS_RABBITMQ_TRANSPORT_MODE=platform-private \
  FS_RABBITMQ_PRIVATE_HOST=rabbitmq.railway.internal \
  ARTIFACT_STORAGE_BACKEND=local_fs PORT=8080 \
  "FS_PUBLIC_BASE_URL=https://$domain" \
  --service compact --project "$project_id" --environment "$environment_name" \
  --skip-deploys --json >/dev/null

compact_id=$(railway service list --json | jq -r '.[] | select(.name == "compact") | .id')
if [[ -z "$compact_id" ]]; then
  printf 'Could not identify the Compact service.\n' >&2
  exit 1
fi
railway api "mutation { serviceInstanceUpdate(serviceId:\"$compact_id\",environmentId:\"$environment_id\",input:{healthcheckPath:\"/health/ready\",healthcheckTimeout:300,drainingSeconds:180,overlapSeconds:0,restartPolicyType:ALWAYS,sleepApplication:false}) }" \
  | jq -e '.data.serviceInstanceUpdate == true' >/dev/null

printf 'PostgreSQL and RabbitMQ are ready; starting Compact last.\n'
railway service source connect --image "$compact_image" --service compact \
  --project "$project_id" --environment "$environment_name" --json >/dev/null

deadline=$((SECONDS + 900))
while (( SECONDS < deadline )); do
  deployment_json=$(railway deployment list --service compact --project "$project_id" \
    --environment "$environment_name" --json)
  compact_deployment_id=$(jq -r '.[0].id // empty' <<<"$deployment_json")
  status=$(jq -r '.[0].status // empty' <<<"$deployment_json")
  case "$status" in
    FAILED|CRASHED|REMOVED)
      printf 'Compact deployment ended with %s. Inspect Railway logs.\n' "$status" >&2
      exit 1 ;;
    SUCCESS)
      if curl --fail --silent --show-error --max-time 10 \
        "https://$domain/health/ready" | jq -e '.ready == true' >/dev/null; then
        printf 'Flow Steward Compact is ready: https://%s\n' "$domain"
        for ((attempt = 0; attempt < 12; attempt++)); do
          setup_log=$(railway logs "$compact_deployment_id" --service compact \
            --project "$project_id" --environment "$environment_name" \
            --lines 20 --filter 'Flow Steward has no administrator yet' --json \
            | jq -rs --arg prefix "https://$domain/bootstrap#setup-token=" \
              '[.[].message? | strings | select(contains($prefix))] | first // empty' || true)
          if [[ -n "$setup_log" ]]; then
            printf '%s\n' "$setup_log"
            printf 'This private setup link expires in 15 minutes. Do not share it.\n'
            exit 0
          fi
          sleep 5
        done
        printf 'Compact is ready, but its first-admin link was not found in the current deployment logs.\n' >&2
        printf 'Inspect the Compact deploy logs. If no admin exists and the link expired, restart only Compact to issue a new one.\n' >&2
        exit 1
      fi ;;
  esac
  sleep 5
done
printf 'Timed out waiting for Compact readiness. Inspect Railway logs.\n' >&2
exit 1
