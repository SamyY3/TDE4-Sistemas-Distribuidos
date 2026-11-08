#!/usr/bin/env bash
# Inicia as 3 instâncias Flask em segundo plano (portas 5001, 5002 e 5003).
# Variável opcional: PYTHON=python3 (comando do Python a usar).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
RUN="$ROOT/run"
mkdir -p "$RUN/pids" "$RUN/logs"

for id in 1 2 3; do
  port=$((5000 + id))   # deve coincidir com config/servers.json e nginx/algorithms/
  pidfile="$RUN/pids/server$id.pid"

  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "Servidor $id já está em execução (PID $(cat "$pidfile"))"
    continue
  fi

  nohup "$PYTHON" "$ROOT/app/app.py" --id "$id" >"$RUN/logs/server$id.log" 2>&1 &
  echo $! >"$pidfile"

  # Espera a instância responder (até ~5 s).
  for _ in $(seq 1 20); do
    curl -fs "http://127.0.0.1:$port/health" >/dev/null 2>&1 && break
    sleep 0.25
  done

  if curl -fs "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    echo "Servidor $id iniciado (PID $(cat "$pidfile")) em http://127.0.0.1:$port"
  else
    echo "ERRO: Servidor $id não respondeu. Veja $RUN/logs/server$id.log" >&2
    exit 1
  fi
done
