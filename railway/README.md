# Railway

Railway has no multi-service Blueprint: its `railway.json` describes a single
service and cannot order three. Railway also starts an image-backed service as
soon as the image is attached, so a Compact service started before its volume
and variables exist writes incomplete state. The guided
[`install.sh`](install.sh) therefore creates everything empty first and attaches
images in dependency order: PostgreSQL, then RabbitMQ, then Compact.

The images are the release pinned in [`release.env`](../release.env), which is
kept on the latest published release automatically.

## Install

You need Bash, the [Railway CLI](https://docs.railway.com/guides/cli), `jq`,
`openssl` and `curl`. Application source is not needed.

```bash
git clone https://github.com/Flow-Steward/flow-steward-deploy.git
cd flow-steward-deploy
bash railway/install.sh
```

The script signs in when needed, asks for the billed workspace and a project
name, and creates a new project. It refuses a linked project that already has
services. It then:

1. creates empty `postgres`, `rabbitmq` and `compact` services with persistent
   volumes at `/var/lib/postgresql/data`, `/var/lib/rabbitmq` and `/data`;
2. generates separate PostgreSQL and RabbitMQ passwords and stores them as
   Railway variables, without printing them;
3. starts PostgreSQL and waits until it accepts connections, then RabbitMQ;
4. creates the public domain, sets Compact's variables (including
   `FS_RABBITMQ_TRANSPORT_MODE=platform-private` for the private broker host),
   readiness path `/health/ready`, Always restart, no deployment overlap and
   180 seconds of draining;
5. starts Compact last, waits for public readiness and prints the private
   first-administrator link.

The link expires after 15 minutes; do not share it. An interrupted run can
leave billable resources: inspect and delete only that project before retrying.
The script is for a fresh project, not for updates.

## Administration

Run the in-container command through Railway SSH from the linked directory:

```bash
railway ssh --service compact -- flow-steward status
railway ssh --service compact -- flow-steward users list
railway ssh --service compact -- flow-steward users create --role admin
```

`railway run` executes on your own machine with injected variables; it is not
the container console.

## Updates

Do not swap the Compact image of a running installation without a backup of
PostgreSQL, RabbitMQ and `/data`. Railway's standard managed PostgreSQL lacks
the required Apache AGE extension, so keep the Flow Steward PostgreSQL image.
