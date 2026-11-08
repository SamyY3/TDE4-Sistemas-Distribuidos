#!/usr/bin/env bash
# Encerra as 3 instâncias Flask iniciadas por start_servers.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/run"

for id in 1 2 3; do
  pidfile="$RUN/pids/server$id.pid"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    kill "$(cat "$pidfile")"
    echo "Servidor $id encerrado"
  else
    echo "Servidor $id não estava em execução"
  fi
  rm -f "$pidfile"
done
