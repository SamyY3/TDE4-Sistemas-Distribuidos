#!/usr/bin/env bash
# Liga ou desliga UMA instância Flask (usado para simular falhas).
# Uso: scripts/server_ctl.sh {start|stop} {1|2|3}
#
# Variáveis opcionais:
#   PYTHON=python3        comando do Python
#   DELAY_MS_<id>=100     latência artificial (ms) da instância <id> ao iniciar
#                         ex.: DELAY_MS_1=100 scripts/server_ctl.sh start 1
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
RUN="$ROOT/run"
ACTION="${1:-}"
ID="${2:-}"

case "$ACTION:$ID" in
  start:[123]|stop:[123]) ;;
  *)
    echo "Uso: $0 {start|stop} {1|2|3}" >&2
    exit 1
    ;;
esac

port=$((5000 + ID))   # deve coincidir com config/servers.json e nginx/algorithms/
pidfile="$RUN/pids/server$ID.pid"
mkdir -p "$RUN/pids" "$RUN/logs"

is_running() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

if [ "$ACTION" = "stop" ]; then
  if is_running; then
    pid="$(cat "$pidfile")"
    kill "$pid"
    # Espera o processo terminar (até ~3 s) para a porta ficar realmente livre.
    for _ in $(seq 1 12); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    echo "Servidor $ID encerrado"
  else
    echo "Servidor $ID não estava em execução"
  fi
  rm -f "$pidfile"
  exit 0
fi

# start
if is_running; then
  echo "Servidor $ID já está em execução (PID $(cat "$pidfile"))"
  exit 0
fi

delay_var="DELAY_MS_$ID"
delay="${!delay_var:-0}"

nohup "$PYTHON" "$ROOT/app/app.py" --id "$ID" --delay-ms "$delay" \
  >"$RUN/logs/server$ID.log" 2>&1 &
echo $! >"$pidfile"

for _ in $(seq 1 20); do
  curl -fs "http://127.0.0.1:$port/health" >/dev/null 2>&1 && break
  sleep 0.25
done

if curl -fs "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
  extra=""
  [ "$delay" -gt 0 ] 2>/dev/null && extra=" com latência artificial de ${delay} ms"
  echo "Servidor $ID iniciado (PID $(cat "$pidfile")) em http://127.0.0.1:$port$extra"
else
  echo "ERRO: Servidor $ID não respondeu. Veja $RUN/logs/server$ID.log" >&2
  exit 1
fi
