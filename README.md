# Flow Steward deployment configuration

This repository contains Render and Elestio configuration for fresh Flow Steward Compact installations. Both pull from the same public [Flow Steward Compact image repository](https://github.com/vasily-piksis/agentic-team/pkgs/container/flow-steward-compact), pinned to a tested digest. They do not build or fork the application image.

## Render

Render creates one Compact web service, a private PostgreSQL service with the required extensions, a private RabbitMQ service, and their persistent disks. The services are paid; review Render's estimate before deploying. The application waits for PostgreSQL and RabbitMQ to accept connections before initialization.

Fresh Blueprint installation was checked on Render on 2026-09-26: readiness,
first-administrator setup, browser login, CLI administration, graceful shutdown,
and user/session/file persistence after restart. The same Compact image also
passed a fresh Railway installation and restart check.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https%3A%2F%2Fgithub.com%2FFlow-Steward%2Fflow-steward-deploy)

This single-instance disk-backed configuration has downtime during replacement;
the check does not certify AI-provider execution or backup/restore.

After the web service is Live, open its logs and use the one-time first-admin URL printed there. The Blueprint is for a **new** installation; it is not an upgrade or migration tool.

The setup URL expires after 15 minutes. If it expires while no administrator
exists, restart only Compact and read its fresh logs. Keep all three disks.
In **flow-steward-compact → Shell**, run administrative commands directly:

```bash
flow-steward users list
flow-steward status
flow-steward users create --role admin
```

The last command is an alternative first-administrator path; enter the email
and password interactively. No Git checkout or manual secret export is needed.
The application is under `/app`, and persistent files are under `/data`.

The tested plans total $140.25/month before traffic overages or taxes:
Compact 2 vCPU/4 GB + 10 GB disk, PostgreSQL 1 vCPU/2 GB + 10 GB disk,
RabbitMQ 1 vCPU/2 GB + 1 GB disk. This is a tested configuration, not a
measured minimum. Confirm Render's current estimate before deploying.
PostgreSQL uses our extension-enabled image, not Render managed PostgreSQL;
arrange backups for PostgreSQL, RabbitMQ and `/data` before storing real data.

## Elestio

The root `docker-compose.yml` and `elestio.yml` run Compact, extension-enabled
PostgreSQL and RabbitMQ on one Elestio CI/CD VM. Only the application is
exposed, through Elestio HTTPS; the database and broker remain private.
The images are the same as in the Render Blueprint.

1. Fork this public configuration repository into your GitHub account.
2. In Elestio, connect GitHub under **CI/CD → GitHub → Import Git Repository**
   and import your fork. No access to the private application source is needed.
3. Choose a new VM, region and plan. The tested configuration was Netcup
   Nuremberg, 4 CPU / 8 GB RAM / 100 GB storage, quoted at $0.0411/hour
   (approximately $30/month at 730 hours). Review the current estimate.
4. Select `main` and name the pipeline `flow-steward-compact`. The template
   fills **Docker Compose**, `docker-compose pull`, `docker-compose up -d`,
   generated environment passwords, and HTTPS443 → HTTP172.17.0.1:3000.
5. Create the pipeline and wait for `/health/ready` to return HTTP200.
   Compact waits for the database and broker before initialization.
6. Open the pipeline's running logs and use the complete one-time setup URL
   to create the first administrator, then sign in. The link expires after
   15 minutes. Keep it private.

Do not paste `random_password` into Elestio's manual Compose environment
editor: that path kept it as a literal password in testing. Importing
`elestio.yml` through GitHub generated the password as expected.

Elestio's **Open terminal** opens the VM host. Run administrative commands
inside Compact:

```bash
cd /opt/app/flow-steward-compact
docker compose exec compact flow-steward --help
docker compose exec compact flow-steward --json users list
docker compose exec compact flow-steward status
docker compose exec compact flow-steward users create --role admin
```

The last command offers interactive administrator creation if you cannot use
the setup link. If you changed the pipeline name, adjust the directory.
Inside Compact, `/app` holds the application and `/data` holds persistent
files. No source checkout or secret exports are required for these commands.

To renew an expired setup link before an administrator exists, restart only
Compact and read its fresh logs:

```bash
docker compose restart compact
docker compose logs --tail=100 compact
```

If an earlier link remains valid, use it or wait for expiry. Keep all three
volumes. A restart briefly interrupts service; this is one Compact instance,
not a zero-downtime cluster. GitHub webhook pushes can trigger redeployment;
review changes before syncing your fork. Arrange and test backups before
storing real data. Delete disposable test pipelines and VMs after testing.

Fresh GitHub-template acceptance on 2026-09-26 covered generated credentials,
HTTPS readiness, first-administrator creation, browser login, CLI commands,
graceful shutdown and user/session/file/runtime-key persistence after restart.
AI-provider execution and full backup/restore were not included. The tested
Compact source was `367d5ff885a5b7557cdb0fb712fe754539fa4d09`, pinned to
`sha256:e41f179da299904b02cd60cb8b50d73e20f7fcf9f384a5bbc8edd17c8bfcf214`.
