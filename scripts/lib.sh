#!/usr/bin/env bash
# Funções compartilhadas pelos scripts de teste. Uso: source scripts/lib.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${URL:-http://127.0.0.1:8080}"
RESULTS="${RESULTS:-$ROOT/resultados}"
ACCESS_LOG="${ACCESS_LOG:-$ROOT/run/nginx/logs/access.log}"

# Envia N requisições sequenciais a $URL (caminho opcional, padrão "/").
# Preenche dois arrays globais, um item por requisição:
#   CODES   = código HTTP ("000" quando não há resposta)
#   SERVERS = ID do servidor que respondeu (cabeçalho X-Server-ID; "-" se não veio)
send_requests() {
  local n=$1 path="${2:-/}" i out code id
  CODES=()
  SERVERS=()
  for ((i = 0; i < n; i++)); do
    out=$(curl -s -o /dev/null -D - --max-time 10 "$URL$path" 2>/dev/null | tr -d '\r')
    code=$(printf '%s\n' "$out" | awk 'NR==1{print $2}')
    id=$(printf '%s\n' "$out" | awk -F': ' 'tolower($1)=="x-server-id"{print $2}')
    CODES+=("${code:-000}")
    SERVERS+=("${id:--}")
  done
}

# Mostra o resumo da última chamada de send_requests.
print_summary() {
  echo "    Total enviado: ${#CODES[@]}"
  echo "    Códigos HTTP:"
  printf '%s\n' "${CODES[@]}" | sort | uniq -c \
    | awk '{printf "      %s: %s\n", $2, $1}'
  echo "    Servidor que respondeu:"
  printf '%s\n' "${SERVERS[@]}" | sort | uniq -c \
    | awk '{n = ($2 == "-") ? "nenhum (sem resposta)" : "Servidor " $2; printf "      %s: %s\n", n, $1}'
}

# Extrai métricas de uma saída do ab.
# Imprime: req_por_seg tempo_medio_ms p95_ms falhas nao_2xx
parse_ab() {
  local f="$1" rps tmean p95 failed non2xx
  rps=$(awk '/^Requests per second:/{print $4; exit}' "$f")
  tmean=$(awk '/^Time per request:/{print $4; exit}' "$f")
  p95=$(awk '$1=="95%"{print $2; exit}' "$f")
  failed=$(awk '/^Failed requests:/{print $3; exit}' "$f")
  non2xx=$(awk '/^Non-2xx responses:/{print $3; exit}' "$f")
  echo "${rps:-NA} ${tmean:-NA} ${p95:-NA} ${failed:-NA} ${non2xx:-0}"
}
