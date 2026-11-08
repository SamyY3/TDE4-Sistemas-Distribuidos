#!/usr/bin/env bash
# Simula falhas: desliga os servidores um a um e verifica, pelo balanceador,
# se o sistema continua respondendo. Roda para os dois algoritmos.
#
# Cenários (por algoritmo):
#   1. 3 servidores ativos
#   2. 2 servidores ativos (servidor 1 desligado)
#   3. 1 servidor ativo   (servidores 1 e 2 desligados)
#   4. 0 servidores ativos (todos desligados)  -> esperado: erro 502
#   5. Recuperação: todos religados             -> os 3 voltam a responder
#
# Pré-requisito: Nginx no ar (scripts/start_nginx.sh) e as 3 instâncias
# iniciadas pelos scripts deste projeto.
# Variáveis opcionais: REQS=30 (requisições por cenário), ALGOS, URL.
# O relatório também é salvo em resultados/falhas_<data>.txt
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REQS="${REQS:-30}"
ALGOS="${ALGOS:-round_robin least_conn}"
FAIL_TIMEOUT=5   # deve coincidir com fail_timeout em nginx/algorithms/*.conf
FAILS=0

# Confere o resultado do cenário recém-executado.
#   $1 = descrição  $2 = IDs que devem responder ("" = nenhum)  $3 = 1 (esperado 200) ou 0 (esperado erro)
check() {
  local ok=1 c s id found
  for c in "${CODES[@]}"; do
    if [ "$3" = 1 ]; then [ "$c" = 200 ] || ok=0; else [ "$c" = 200 ] && ok=0; fi
  done
  if [ "$3" = 1 ]; then
    for s in "${SERVERS[@]}"; do
      case " $2 " in *" $s "*) ;; *) ok=0 ;; esac
    done
    for id in $2; do
      found=0
      for s in "${SERVERS[@]}"; do [ "$s" = "$id" ] && found=1; done
      [ "$found" = 1 ] || ok=0
    done
  fi
  if [ "$ok" = 1 ]; then
    echo "    [OK] $1"
  else
    echo "    [FALHA] $1"
    FAILS=$((FAILS + 1))
  fi
}

scenario() {   # $1 título  $2 IDs esperados  $3 esperado sucesso (1/0)
  echo
  echo "  >> $1"
  send_requests "$REQS"
  print_summary
  check "$1" "$2" "$3"
}

main() {
  echo "Teste de falhas - $(date '+%d/%m/%Y %H:%M:%S') - $REQS requisições por cenário"

  for algo in $ALGOS; do
    echo
    echo "================================================"
    echo " ALGORITMO: $algo"
    echo "================================================"
    "$ROOT/scripts/set_algorithm.sh" "$algo" | sed 's/^/  /'
    "$ROOT/scripts/start_servers.sh" >/dev/null
    sleep $((FAIL_TIMEOUT + 1))   # garante que nenhum servidor esteja marcado como falho

    scenario "1. Três servidores ativos" "1 2 3" 1

    "$ROOT/scripts/server_ctl.sh" stop 1 | sed 's/^/  /'
    scenario "2. Dois servidores ativos (servidor 1 desligado)" "2 3" 1

    "$ROOT/scripts/server_ctl.sh" stop 2 | sed 's/^/  /'
    scenario "3. Um servidor ativo (apenas o servidor 3)" "3" 1

    "$ROOT/scripts/server_ctl.sh" stop 3 | sed 's/^/  /'
    scenario "4. Nenhum servidor ativo (esperado: erro 502)" "" 0

    "$ROOT/scripts/start_servers.sh" | sed 's/^/  /'
    sleep $((FAIL_TIMEOUT + 1))
    scenario "5. Recuperação (todos religados)" "1 2 3" 1
  done

  echo
  echo "================================================"
  if [ "$FAILS" = 0 ]; then
    echo " RESULTADO FINAL: todos os cenários passaram"
  else
    echo " RESULTADO FINAL: $FAILS verificação(ões) com FALHA"
  fi
  echo "================================================"
  [ "$FAILS" = 0 ]   # código de saída de main: 0 = tudo certo
}

if ! curl -s --max-time 5 -o /dev/null "$URL/health"; then
  echo "ERRO: balanceador não responde em $URL. Inicie com scripts/start_servers.sh e scripts/start_nginx.sh" >&2
  exit 1
fi

mkdir -p "$RESULTS"
OUT="$RESULTS/falhas_$(date +%Y%m%d_%H%M%S).txt"
trap '"$ROOT/scripts/start_servers.sh" >/dev/null 2>&1' EXIT   # sempre deixa os 3 no ar
main 2>&1 | tee "$OUT"
status=${PIPESTATUS[0]}   # main roda dentro do pipe: usa o status dele, não o do tee
echo "Relatório salvo em: $OUT"
exit "$status"
