#!/usr/bin/env bash
# Inicia o Nginx (balanceador) na porta 8080, sem precisar de root.
# Se nenhum algoritmo foi escolhido ainda, usa round_robin.
# Variável opcional: NGINX=/caminho/do/nginx
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_nginx

NGINX_DIR="$ROOT/nginx"
RUN="$ROOT/run/nginx"
mkdir -p "$RUN/logs" "$RUN/temp"

if [ ! -f "$NGINX_DIR/upstream.active.conf" ]; then
  bash "$ROOT/scripts/set_algorithm.sh" round_robin
fi

if pid_alive "$RUN/nginx.pid" nginx; then
  echo "Nginx já está em execução (PID $(cat "$RUN/nginx.pid"))"
  exit 0
fi
rm -f "$RUN/nginx.pid"   # PID antigo (por exemplo, após reiniciar o WSL)

"$NGINX" -p "$RUN/" -c "$NGINX_DIR/nginx.conf" -t
"$NGINX" -p "$RUN/" -c "$NGINX_DIR/nginx.conf"

sleep 0.5
if ! pid_alive "$RUN/nginx.pid" nginx; then
  echo "ERRO: o Nginx não ficou em execução. Veja $RUN/logs/error.log" >&2
  exit 1
fi
echo "Nginx iniciado em $URL"
echo "Log de acessos: $RUN/logs/access.log"
