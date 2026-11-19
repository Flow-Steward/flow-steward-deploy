# VPS: DigitalOcean Droplet, Hostinger, Hetzner and other Docker hosts

Any Linux server where you control Docker uses the standard Flow Steward
installer from the application repository. There is no provider-specific image
or App Platform file: a DigitalOcean Droplet, a Hostinger VPS or a Hetzner Cloud
server all follow these steps.

## Prepare the server

- amd64 (`x86_64`) or arm64 (`aarch64`) Linux, 4 GB RAM or more (the recorded
  DigitalOcean check used 4 vCPU / 8 GB) and enough disk for images and data;
- a non-root deployment user with access to
  [Docker Engine](https://docs.docker.com/engine/install/) and the
  [Compose v2 plugin](https://docs.docker.com/compose/install/linux/), plus Git
  and curl;
- for a public HTTPS site, a DNS name pointing at the server and ports 80/443
  open, or an existing reverse proxy that will own TLS.

DigitalOcean's Docker Marketplace image and Hostinger's Docker VPS templates
preinstall Docker; still check `docker compose version` as the deployment user.

## Install the latest release

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Flow-Steward/flow-steward-deploy/main/vps/install.sh)
```

[`install.sh`](install.sh) asks GitHub for the latest published release when it
runs, clones the application repository at that release tag into
`./flow-steward` and starts its guided `./install.sh`. A checkout at a release
tag installs that release's official images; nothing is built from source.
Arguments are passed to the installer, for example `--plain`. Set
`FS_INSTALL_DIR` to use another directory.

The equivalent manual commands:

```bash
tag=$(curl -fsSL https://api.github.com/repos/Flow-Steward/flow-steward-app/releases/latest | grep -oE '"tag_name": *"[^"]+"' | cut -d'"' -f4)
git clone --branch "$tag" https://github.com/Flow-Steward/flow-steward-app.git flow-steward
cd flow-steward && ./install.sh
```

Use a full clone, without `--depth`. The installer asks for the profile,
ingress/TLS and public host; the
[installer walkthrough](https://docs.flowsteward.org/docs/deploy/installer-walkthrough)
explains every question. Then check:

```bash
./flow-steward status
./flow-steward doctor
```

## Updates

From the checkout, the CLI finds the newest release, enables maintenance, backs
up the database and applies migrations:

```bash
./flow-steward release check
./flow-steward release upgrade --confirm
```
