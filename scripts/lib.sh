#!/usr/bin/env bash
# Funções compartilhadas pelos scripts. Uso: source scripts/lib.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${URL:-http://127.0.0.1:8080}"
NGINX="${NGINX:-nginx}"
RESULTS="${RESULTS:-$ROOT/resultados}"
ACCESS_LOG="${ACCESS_LOG:-$ROOT/run/nginx/logs/access.log}"

# Retorna 0 se o processo $1 (PID) existe e não é um zumbi.
proc_up() {
  kill -0 "$1" 2>/dev/null || return 1
  ps -p "$1" -o stat= 2>/dev/null | grep -q '^Z' && return 1
  return 0
}

# Retorna 0 se o arquivo de PID $1 aponta para um processo VIVO cuja linha de
# comando contém $2. Só "kill -0" não basta: depois de reiniciar o WSL (ou o PC),
# o PID guardado pode ter sido reaproveitado por outro programa; sem esta
# conferência o script diria "já em execução" ou poderia encerrar o processo errado.
pid_alive() {
  local pidfile="$1" pattern="$2" pid cmd
  [ -f "$pidfile" ] || return 1
  pid="$(cat "$pidfile" 2>/dev/null)"
  [ -n "$pid" ] || return 1
  proc_up "$pid" || return 1
  cmd="$(ps -p "$pid" -o args= 2>/dev/null || tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)"
  case "$cmd" in *"$pattern"*) return 0 ;; *) return 1 ;; esac
}

# Falha com mensagem clara se o Nginx não estiver instalado.
require_nginx() {
  if ! command -v "$NGINX" >/dev/null 2>&1; then
    echo "ERRO: Nginx não encontrado ('$NGINX'). Instale com: sudo apt install nginx" >&2
    return 1
  fi
}

# Lê linhas do log de acessos do Nginx (entrada padrão) e imprime "s1 s2 s3": quantas
# requisições cada servidor atendeu. Se a requisição foi reenviada a outra instância,
# o log traz algo como "servidor=-, 2"; vale o ÚLTIMO valor (quem de fato respondeu).
count_by_server() {
  sed -n 's/.*servidor=\(.*\) upstream=.*/\1/p' \
    | awk -F'[, ]+' '{ id = $NF; if (id == 1 || id == 2 || id == 3) c[id]++ }
                     END { print c[1] + 0, c[2] + 0, c[3] + 0 }'
}

# Retorna 0 se as 3 instâncias respondem em /health direto (sem passar pelo Nginx).
all_servers_up() {
  local p
  for p in 5001 5002 5003; do
    curl -fs --max-time 3 "http://127.0.0.1:$p/health" >/dev/null 2>&1 || return 1
  done
}

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
