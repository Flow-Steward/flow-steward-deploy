# Flow Steward deployment configuration

This repository contains the Render Blueprint for a fresh Flow Steward Compact installation. It does not build or fork the application image: `render.yaml` pulls the same public [Flow Steward Compact image](https://github.com/vasily-piksis/agentic-team/pkgs/container/flow-steward-compact) used by other platforms, pinned to a tested digest.

Render creates one Compact web service, a private PostgreSQL service with the required extensions, a private RabbitMQ service, and their persistent disks. The services are paid; review Render's estimate before deploying. The application waits for PostgreSQL and RabbitMQ to accept connections before initialization.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https%3A%2F%2Fgithub.com%2FFlow-Steward%2Fflow-steward-deploy)

After the web service is Live, open its logs and use the one-time first-admin URL printed there. The Blueprint is for a **new** installation; it is not an upgrade or migration tool.
