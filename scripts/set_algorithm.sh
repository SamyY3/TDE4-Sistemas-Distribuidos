#!/usr/bin/env bash
# Alterna o algoritmo de balanceamento.
# Uso: scripts/set_algorithm.sh round_robin | least_conn
# Se o Nginx estiver rodando, recarrega a configuração sem derrubá-lo.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX="${NGINX:-nginx}"
NGINX_DIR="$ROOT/nginx"
RUN="$ROOT/run/nginx"
ALGO="${1:-}"

case "$ALGO" in
  round_robin|least_conn) ;;
  *)
    echo "Uso: $0 {round_robin|least_conn}" >&2
    exit 1
    ;;
esac

cp "$NGINX_DIR/algorithms/$ALGO.conf" "$NGINX_DIR/upstream.active.conf"
echo "Algoritmo ativo: $ALGO"

if [ -f "$RUN/nginx.pid" ] && kill -0 "$(cat "$RUN/nginx.pid")" 2>/dev/null; then
  "$NGINX" -p "$RUN/" -c "$NGINX_DIR/nginx.conf" -t || exit 1
  "$NGINX" -p "$RUN/" -c "$NGINX_DIR/nginx.conf" -s reload
  echo "Nginx recarregado."
else
  echo "Nginx não está em execução; o algoritmo será usado na próxima inicialização."
fi
