#!/usr/bin/env bash
# Demonstra Round Robin e Least Connections pelo balanceador.
# Uso: bash scripts/demo_algoritmos.sh [URL]   (padrão: http://127.0.0.1:8080)
#
# Para cada algoritmo, faz dois testes:
#   A) 9 requisições em sequência: mostra a ordem dos servidores.
#   B) Deixa UM servidor ocupado (requisição /slow de 4 s) e envia 9
#      requisições rápidas: mostra quantas o servidor ocupado recebeu.
#      Round Robin ignora a ocupação; Least Connections evita o servidor ocupado.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

URL="${1:-$URL}"
N=9
SEQ=()

if ! curl -s --max-time 5 -o /dev/null "$URL/health"; then
  echo "ERRO: balanceador não responde em $URL. Inicie com scripts/start_servers.sh e scripts/start_nginx.sh" >&2
  exit 1
fi
if ! all_servers_up; then
  echo "AVISO: nem todas as 3 instâncias respondem; a demonstração só faz sentido com as 3 no ar." >&2
fi

# Envia $1 requisições rápidas e guarda em SEQ o ID do servidor de cada resposta.
fast_requests() {
  local i id
  SEQ=()
  for ((i = 0; i < $1; i++)); do
    id=$(curl -s -o /dev/null -D - "$URL/" | tr -d '\r' \
         | awk -F': ' 'tolower($1)=="x-server-id"{print $2}')
    SEQ+=("${id:-erro}")
  done
}

# Quantas vezes o servidor $1 aparece em SEQ.
count_in_seq() {
  local c=0 x
  for x in "${SEQ[@]}"; do [ "$x" = "$1" ] && c=$((c + 1)); done
  echo "$c"
}

for algo in round_robin least_conn; do
  echo "=============================================="
  echo " ALGORITMO: $algo"
  echo "=============================================="
  bash "$ROOT/scripts/set_algorithm.sh" "$algo" | sed 's/^/  /'
  sleep 1

  echo
  echo " Teste A - $N requisições em sequência:"
  fast_requests "$N"
  echo "   Ordem dos servidores: ${SEQ[*]}"

  echo
  echo " Teste B - um servidor ocupado + $N requisições rápidas:"
  hdr="$(mktemp)"
  curl -s -o /dev/null -D "$hdr" "$URL/slow?s=4" &
  slow_pid=$!
  sleep 0.5
  fast_requests "$N"
  wait "$slow_pid"
  busy=$(tr -d '\r' <"$hdr" | awk -F': ' 'tolower($1)=="x-server-id"{print $2}')
  rm -f "$hdr"
  echo "   Servidor ocupado (atendendo /slow): ${busy:-?}"
  echo "   Ordem dos servidores nas rápidas:   ${SEQ[*]}"
  echo "   Rápidas enviadas ao servidor ocupado: $(count_in_seq "${busy:-?}") de $N"
  echo
done
