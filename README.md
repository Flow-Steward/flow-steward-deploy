# Flow Steward deployment configuration

This repository contains the Render Blueprint for a fresh Flow Steward Compact installation. It does not build or fork the application image: `render.yaml` pulls from the same public [Flow Steward Compact image repository](https://github.com/vasily-piksis/agentic-team/pkgs/container/flow-steward-compact) used by other platforms, pinned to a tested digest.

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
