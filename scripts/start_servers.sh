#!/usr/bin/env bash
# Inicia as 3 instâncias Flask em segundo plano (portas 5001, 5002 e 5003).
# Variáveis opcionais: PYTHON e DELAY_MS_1/2/3 (ver server_ctl.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for id in 1 2 3; do
  bash "$ROOT/scripts/server_ctl.sh" start "$id"
done
