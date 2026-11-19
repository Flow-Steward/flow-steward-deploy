# Elestio


The root [`docker-compose.yml`](../docker-compose.yml) and
[`elestio.yml`](../elestio.yml) run Compact, extension-enabled PostgreSQL and
RabbitMQ on one Elestio CI/CD VM. Elestio reads both from the repository root,
so they stay there. Their images are the release pinned in
[`release.env`](../release.env), kept current automatically. Only the application is
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
review changes before syncing your fork. Syncing a fork after a new release
changes the image of an existing installation: back up PostgreSQL, RabbitMQ and
`/data` first. Arrange and test backups before
storing real data. Delete disposable test pipelines and VMs after testing.

Fresh GitHub-template acceptance on 2026-09-28 covered generated credentials,
HTTPS readiness, first-administrator creation, browser login, CLI commands,
graceful shutdown and user/session/file/runtime-key persistence after restart.
AI-provider execution and full backup/restore were not included. Each new
release is pinned here automatically; the dated check is not repeated for
every release.
