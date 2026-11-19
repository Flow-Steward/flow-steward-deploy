# Flow Steward deployment configuration

Ready-made Flow Steward installations for hosting providers, one folder per
provider. All of them install the **latest published Flow Steward release**.
No configuration here names a release by hand.

| Provider | Layout | Start here |
| --- | --- | --- |
| [Render](render/README.md) | Compact web service, private PostgreSQL and RabbitMQ | Deploy button / [`render.yaml`](render.yaml) |
| [Railway](railway/README.md) | Compact, PostgreSQL and RabbitMQ services | `bash railway/install.sh` |
| [Fly.io](fly/README.md) | Compact, PostgreSQL and RabbitMQ apps | `bash fly/install.sh` |
| [Elestio](elestio/README.md) | Compact, PostgreSQL and RabbitMQ on one VM | Import this repository; [`elestio.yml`](elestio.yml) |
| [VPS](vps/README.md): DigitalOcean Droplet, Hostinger, Hetzner, any Docker host | Compact or Scalable via the guided installer | `vps/install.sh` |

Render and Elestio read their files from the repository root, so `render.yaml`,
`elestio.yml` and `docker-compose.yml` stay there; everything else lives in the
provider's folder.

## How the release stays current

- [`release.env`](release.env) records the one pinned release and the immutable
  digests of its Compact, PostgreSQL and RabbitMQ images. Every provider file
  repeats exactly those references; the Railway installer reads them from
  `release.env`.
- The [sync-release workflow](.github/workflows/sync-release.yml) runs hourly
  (and on demand). When a newer release is published, it reads that release's
  verified registry digests and its RabbitMQ image, checks that each one can be
  pulled anonymously, rewrites `release.env` and every pin, runs the tests and
  commits the result to `main`.
- The [check workflow](.github/workflows/check.yml) rejects a change whose pins
  differ from `release.env`, that uses a mutable image tag such as `:latest`,
  or that writes a release number by hand.
- The VPS installer needs no pin: it asks GitHub for the latest release when it
  runs.

Images are pinned by digest rather than a moving `latest` tag on purpose: an
existing installation must not change version when a provider restarts or
redeploys it. A new pin applies to new installations; upgrade an existing one
deliberately, after backing up PostgreSQL, RabbitMQ and `/data`.

To pin by hand (for example, to roll back to an earlier release):

```bash
python3 scripts/sync-release.py --version <X.Y.Z>
bash tests/run.sh
```

## Shared notes

Flow Steward refuses unencrypted AMQP unless the deployment declares its broker.
Render, Railway and Fly.io reach RabbitMQ over the provider's private network,
so their Compact settings declare that one host with
`FS_RABBITMQ_TRANSPORT_MODE=platform-private` and `FS_RABBITMQ_PRIVATE_HOST`.
Elestio runs one Compose network on one VM and uses the `compose-local` context
with the broker alias `rabbitmq-fs`. See the
[RabbitMQ transport reference](https://docs.flowsteward.org/reference/environment-variables#rabbitmq-transport).
None of these configurations builds or forks the application image, and none
needs access to application source.

Every hosted example is a fresh, single-instance installation: replacing the
Compact container interrupts service. Arrange and test backups of PostgreSQL,
RabbitMQ and `/data` before storing real data.

## Adding a provider

Create `<provider>/README.md` and the provider's files. Write image references
exactly as in `release.env` (or read `release.env` from a script); the sync
workflow then keeps them current. Add an offline test under `tests/` and call it
from `tests/run.sh`.
