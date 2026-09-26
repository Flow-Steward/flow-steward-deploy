# Fly.io Compact installation

These three `fly.toml` examples use the same public, pinned images as Render
and Elestio. Fly runs each image in its own app; one TOML does not describe
a Docker Compose stack or order deployments across apps.

This is a fresh, single-instance installation with local persistent storage,
not an upgrade tool or a high-availability database configuration. Keep all
three apps in the same Fly organization and region. Only Compact has public
ports. PostgreSQL and RabbitMQ use Fly's private IPv6 network.

## Prepare

Install [flyctl](https://fly.io/docs/flyctl/install/) and run `fly auth login`.
Add billing before a persistent test: the free trial stops Machines after
five minutes. Review current prices before creating resources. This example
uses Compact 2 performance CPUs / 4 GB RAM, PostgreSQL 1 / 2 GB, RabbitMQ 1 / 2 GB,
and 10 GB / 10 GB / 1 GB volumes. These are tested sizes, not measured minima.

Compact uses performance CPUs because its restart on two shared CPUs did
not reach readiness within ten minutes after CPU burst credits were spent.
Linux reported about 76% CPU steal time. With only CPU kind changed, the same
image/memory/volume reached readiness in about 2–3 minutes. See
[Fly's CPU performance documentation](https://fly.io/docs/machines/cpu-performance/).

Clone this public configuration repository; application source is not needed:

```sh
git clone https://github.com/Flow-Steward/flow-steward-deploy.git
cd flow-steward-deploy
```

Choose a globally unique prefix, such as `mycompany-fs`, and replace
`your-fs-demo` in all three TOMLs with it. Set `primary_region` consistently
if Frankfurt (`fra`) is unsuitable. In the following commands use that same
prefix and your actual organization slug (`fly orgs list`):

```sh
FS_FLY_PREFIX=mycompany-fs
FS_FLY_ORG=personal
FS_FLY_REGION=fra

fly config validate --strict -c fly/postgres.toml
fly config validate --strict -c fly/rabbitmq.toml
fly config validate --strict -c fly/compact.toml

fly apps create "$FS_FLY_PREFIX-pg" --org "$FS_FLY_ORG"
fly apps create "$FS_FLY_PREFIX-rabbit" --org "$FS_FLY_ORG"
fly apps create "$FS_FLY_PREFIX-compact" --org "$FS_FLY_ORG"

fly volumes create postgres_data -a "$FS_FLY_PREFIX-pg" --region "$FS_FLY_REGION" --size 10 --yes
fly volumes create rabbitmq_data -a "$FS_FLY_PREFIX-rabbit" --region "$FS_FLY_REGION" --size 1 --yes
fly volumes create compact_data -a "$FS_FLY_PREFIX-compact" --region "$FS_FLY_REGION" --size 10 --yes
```

Generate separate passwords locally and send matching values to dependencies
and Compact through stdin. Do not put passwords in TOMLs or commit them:

```sh
FS_PG_PASSWORD=$(openssl rand -hex 32)
FS_RABBIT_PASSWORD=$(openssl rand -hex 32)
printf 'POSTGRES_PASSWORD=%s\n' "$FS_PG_PASSWORD" | fly secrets import -a "$FS_FLY_PREFIX-pg"
printf 'RABBITMQ_DEFAULT_PASS=%s\n' "$FS_RABBIT_PASSWORD" | fly secrets import -a "$FS_FLY_PREFIX-rabbit"
printf 'POSTGRES_PASSWORD=%s\nRABBITMQ_PASS=%s\n' "$FS_PG_PASSWORD" "$FS_RABBIT_PASSWORD" | fly secrets import -a "$FS_FLY_PREFIX-compact"
unset FS_PG_PASSWORD FS_RABBIT_PASSWORD

fly ips allocate-v6 -a "$FS_FLY_PREFIX-compact"
fly ips allocate-v4 --shared -a "$FS_FLY_PREFIX-compact"
```

## Start in order

Run these steps sequentially. Stop if a deploy or readiness command fails;
inspect its logs before continuing. `--ha=false` keeps one Machine per volume.
Do not clone or scale these Machines without designing replication/storage.

```sh
fly deploy -c fly/postgres.toml --ha=false --yes --wait-timeout 10m
fly ssh console -a "$FS_FLY_PREFIX-pg" -C 'pg_isready -U flow_steward -d flow_steward'

fly deploy -c fly/rabbitmq.toml --ha=false --yes --wait-timeout 10m
fly ssh console -a "$FS_FLY_PREFIX-rabbit" -C 'rabbitmq-diagnostics -q ping'

fly deploy -c fly/compact.toml --ha=false --yes --wait-timeout 10m
curl --fail "https://$FS_FLY_PREFIX-compact.fly.dev/health/ready"
fly ssh console -a "$FS_FLY_PREFIX-compact" -C 'flow-steward status'
```

Compact also waits for both dependencies before initializing. Full role
startup can take several minutes; a Machine marked `started` is not yet
application readiness. Auto-stop is disabled because workers need to run
without incoming web requests.

## First administrator and administration

Open Compact logs and use the private one-time bootstrap URL printed there:

```sh
fly logs -a "$FS_FLY_PREFIX-compact"
```

The URL expires after 15 minutes. Never share it. Opening the public address
without it shows a token field. Alternatively, create the administrator from
the running Machine, with email/password entered interactively:

```sh
fly ssh console -a "$FS_FLY_PREFIX-compact" --pty -C 'flow-steward users create --role admin'
```

Then open `https://<prefix>-compact.fly.dev` and sign in. Commands are on
`PATH`; there is no need to find a Git checkout or export database secrets:

```sh
fly ssh console -a "$FS_FLY_PREFIX-compact" -C 'flow-steward --help'
fly ssh console -a "$FS_FLY_PREFIX-compact" -C 'flow-steward users list'
fly ssh console -a "$FS_FLY_PREFIX-compact" -C 'flow-steward doctor'
```

`fly ssh console` connects to the existing installation. `fly console` creates
a separate temporary Machine and is not the administration path. Application
files are under `/app`; persistent files are under `/data`.

To restart Compact, retaining volumes:

```sh
fly apps restart "$FS_FLY_PREFIX-compact"
```

The TOML configures SIGTERM and a shutdown allowance. Avoid force-stop and
`fly machine restart --time 180`: that command's timeout was rejected by the
Machines API in testing. A single-instance restart interrupts availability.
Keep PostgreSQL and RabbitMQ running while Compact drains. For planned
maintenance, stop Compact before stopping dependencies; start dependencies
and check them before starting Compact again.

Arrange and test backups of all three stores before using real data. Volume
snapshots alone do not prove a consistent PostgreSQL/RabbitMQ backup.

## Remove a disposable test

The following deletes the apps and their data. Use only the exact names of
your disposable test installation, never a production prefix:

```sh
fly apps destroy "$FS_FLY_PREFIX-compact"
fly apps destroy "$FS_FLY_PREFIX-rabbit"
fly apps destroy "$FS_FLY_PREFIX-pg"
fly apps list
```

Verify the apps and volumes are gone; stopping Machines alone retains billed
storage. Preserve any backups you actually need before deletion.
