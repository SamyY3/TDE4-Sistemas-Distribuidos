#!/usr/bin/env bash
# Encerra as 3 instâncias Flask.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for id in 1 2 3; do
  bash "$ROOT/scripts/server_ctl.sh" stop "$id"
done
