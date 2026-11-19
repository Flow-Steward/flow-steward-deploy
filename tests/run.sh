#!/usr/bin/env bash
# Every offline check of this repository. Live provider acceptance is separate.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
python3 scripts/sync-release.py --check
python3 -m unittest discover -s tests -p 'test_*.py'
for script in fly/install.sh railway/install.sh vps/install.sh tests/*.sh; do
  bash -n "$script"
done
bash tests/fly-install.sh
bash tests/railway-install.sh
bash tests/vps-install.sh
