#!/usr/bin/env bash
# Encerra o Nginx iniciado por start_nginx.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

RUN="$ROOT/run/nginx"

if pid_alive "$RUN/nginx.pid" nginx; then
  require_nginx || exit 1
  "$NGINX" -p "$RUN/" -c "$ROOT/nginx/nginx.conf" -s stop
  # Espera o Nginx terminar (até ~5 s).
  for _ in $(seq 1 20); do pid_alive "$RUN/nginx.pid" nginx || break; sleep 0.25; done
  echo "Nginx encerrado"
else
  rm -f "$RUN/nginx.pid"
  echo "Nginx não estava em execução"
fi
