#!/usr/bin/env bash
# Encerra o Nginx iniciado por start_nginx.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX="${NGINX:-nginx}"
RUN="$ROOT/run/nginx"

if [ -f "$RUN/nginx.pid" ] && kill -0 "$(cat "$RUN/nginx.pid")" 2>/dev/null; then
  "$NGINX" -p "$RUN/" -c "$ROOT/nginx/nginx.conf" -s stop
  echo "Nginx encerrado"
else
  echo "Nginx não estava em execução"
fi
