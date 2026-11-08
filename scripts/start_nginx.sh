#!/usr/bin/env bash
# Inicia o Nginx (balanceador) na porta 8080, sem precisar de root.
# Se nenhum algoritmo foi escolhido ainda, usa round_robin.
# Variável opcional: NGINX=/caminho/do/nginx
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX="${NGINX:-nginx}"
NGINX_DIR="$ROOT/nginx"
RUN="$ROOT/run/nginx"

mkdir -p "$RUN/logs" "$RUN/temp"

if [ ! -f "$NGINX_DIR/upstream.active.conf" ]; then
  "$ROOT/scripts/set_algorithm.sh" round_robin
fi

if [ -f "$RUN/nginx.pid" ] && kill -0 "$(cat "$RUN/nginx.pid")" 2>/dev/null; then
  echo "Nginx já está em execução (PID $(cat "$RUN/nginx.pid"))"
  exit 0
fi

"$NGINX" -p "$RUN/" -c "$NGINX_DIR/nginx.conf" -t
"$NGINX" -p "$RUN/" -c "$NGINX_DIR/nginx.conf"
echo "Nginx iniciado em http://127.0.0.1:8080"
echo "Log de acessos: $RUN/logs/access.log"
