#!/usr/bin/env bash
# Liga ou desliga UMA instância Flask (usado para simular falhas).
# Uso: scripts/server_ctl.sh {start|stop} {1|2|3}
#
# Python usado: variável PYTHON; se não houver, o venv do projeto (venv/ ou .venv/);
# se não houver, "python3".
# Variável opcional:
#   DELAY_MS_<id>=100   latência artificial (ms) da instância <id> ao iniciar
#                       ex.: DELAY_MS_1=100 bash scripts/server_ctl.sh start 1
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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

if [ "$ACTION" = "stop" ]; then
  if pid_alive "$pidfile" "app/app.py"; then
    pid="$(cat "$pidfile")"
    kill "$pid" 2>/dev/null
    # Espera o processo terminar (até ~3 s) para a porta ficar realmente livre.
    for _ in $(seq 1 12); do proc_up "$pid" || break; sleep 0.25; done
    proc_up "$pid" && kill -9 "$pid" 2>/dev/null
    echo "Servidor $ID encerrado"
  else
    echo "Servidor $ID não estava em execução"
  fi
  rm -f "$pidfile"
  exit 0
fi

# ---- start ----
if pid_alive "$pidfile" "app/app.py"; then
  echo "Servidor $ID já está em execução (PID $(cat "$pidfile"))"
  exit 0
fi
rm -f "$pidfile"   # PID antigo ou reaproveitado (por exemplo, após reiniciar o WSL)

if ! command -v curl >/dev/null 2>&1; then
  echo "ERRO: curl não encontrado. Instale com: sudo apt install curl" >&2
  exit 1
fi

if [ -z "${PYTHON:-}" ]; then
  PYTHON=python3
  if [ -z "${VIRTUAL_ENV:-}" ]; then
    for v in venv .venv; do
      if [ -x "$ROOT/$v/bin/python" ]; then PYTHON="$ROOT/$v/bin/python"; break; fi
    done
  fi
fi

delay_var="DELAY_MS_$ID"
delay="${!delay_var:-0}"

nohup "$PYTHON" "$ROOT/app/app.py" --id "$ID" --delay-ms "$delay" \
  >"$RUN/logs/server$ID.log" 2>&1 &
pid=$!
echo "$pid" >"$pidfile"

# Pronto quando o /health responde COM O PID DESTE PROCESSO. Isso evita um falso
# sucesso caso outro programa já esteja usando a porta (o health check responderia por ele).
ready=0
for _ in $(seq 1 40); do   # até ~10 s: a primeira partida pode ser lenta (ex.: projeto em /mnt/c no WSL)
  proc_up "$pid" || break
  if curl -fs "http://127.0.0.1:$port/health" 2>/dev/null | grep -qE "\"pid\": ?$pid[,}]"; then
    ready=1
    break
  fi
  sleep 0.25
done

if [ "$ready" = 1 ]; then
  extra=""
  [ "$delay" -gt 0 ] 2>/dev/null && extra=" com latência artificial de ${delay} ms"
  echo "Servidor $ID iniciado (PID $pid) em http://127.0.0.1:$port$extra"
else
  echo "ERRO: Servidor $ID não iniciou (porta $port ocupada? Flask instalado? venv ativo?)." >&2
  echo "Últimas linhas de $RUN/logs/server$ID.log:" >&2
  tail -n 5 "$RUN/logs/server$ID.log" 2>/dev/null | sed 's/^/    /' >&2
  # Se o processo ainda estiver vivo (início muito lento), encerra-o: sem pidfile ele
  # ficaria órfão, segurando a porta, e a próxima tentativa falharia com "porta ocupada".
  if proc_up "$pid"; then kill "$pid" 2>/dev/null; sleep 0.3; proc_up "$pid" && kill -9 "$pid" 2>/dev/null; fi
  rm -f "$pidfile"
  exit 1
fi
