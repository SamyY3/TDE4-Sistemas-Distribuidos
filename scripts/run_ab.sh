#!/usr/bin/env bash
# Testes de carga com Apache Benchmark (ab): compara Round Robin e Least Connections
# com diferentes quantidades de requisições e níveis de concorrência.
#
# Pré-requisitos: ab instalado (pacote apache2-utils), Nginx no ar e as 3 instâncias
# iniciadas (scripts/start_servers.sh e scripts/start_nginx.sh).
#
# Variáveis opcionais:
#   CASOS="100:10 1000:50 5000:100"   pares REQUISIÇÕES:CONCORRÊNCIA
#   ALGOS="round_robin least_conn"
#   CAMINHO=/                         caminho testado (ex.: /slow?s=0.05)
#   TAG=servidor_lento                sufixo dos arquivos, para separar cenários
#   URL=http://127.0.0.1:8080         endereço do balanceador
#
# Saídas em resultados/:
#   ab/<algoritmo>_n<N>_c<C><TAG>.txt   saída completa do ab
#   resumo_ab<TAG>.csv                  tabela-resumo das métricas
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CASOS="${CASOS:-100:10 1000:50 5000:100}"
ALGOS="${ALGOS:-round_robin least_conn}"
CAMINHO="${CAMINHO:-/}"
TAG="${TAG:+_$TAG}"

if ! command -v ab >/dev/null 2>&1; then
  echo "ERRO: 'ab' não encontrado. Instale com: sudo apt install apache2-utils" >&2
  exit 1
fi
if ! curl -s --max-time 5 -o /dev/null "$URL/health"; then
  echo "ERRO: balanceador não responde em $URL. Inicie com scripts/start_servers.sh e scripts/start_nginx.sh" >&2
  exit 1
fi

mkdir -p "$RESULTS/ab"
CSV="$RESULTS/resumo_ab$TAG.csv"
echo "algoritmo,requisicoes,concorrencia,req_por_seg,tempo_medio_ms,p95_ms,falhas,nao_2xx,servidor1,servidor2,servidor3" >"$CSV"

for algo in $ALGOS; do
  "$ROOT/scripts/set_algorithm.sh" "$algo" | sed 's/^/  /'
  sleep 1

  for caso in $CASOS; do
    n="${caso%%:*}"
    c="${caso##*:}"
    raw="$RESULTS/ab/${algo}_n${n}_c${c}$TAG.txt"

    # Marca onde o log de acessos do Nginx está, para contar só este teste.
    before=0
    [ -f "$ACCESS_LOG" ] && before=$(wc -l <"$ACCESS_LOG")

    echo "  [$algo] ab -n $n -c $c $URL$CAMINHO"
    # -l: aceita respostas de tamanho variável (a página muda a cada requisição)
    ab -l -n "$n" -c "$c" "$URL$CAMINHO" >"$raw" 2>&1

    read -r rps tmean p95 failed non2xx < <(parse_ab "$raw")

    s1=NA s2=NA s3=NA
    if [ -f "$ACCESS_LOG" ]; then
      slice=$(tail -n +"$((before + 1))" "$ACCESS_LOG")
      s1=$(printf '%s\n' "$slice" | grep -c 'servidor=1')
      s2=$(printf '%s\n' "$slice" | grep -c 'servidor=2')
      s3=$(printf '%s\n' "$slice" | grep -c 'servidor=3')
    fi

    echo "$algo,$n,$c,$rps,$tmean,$p95,$failed,$non2xx,$s1,$s2,$s3" >>"$CSV"
    sleep 2
  done
done

echo
echo "=== RESUMO ($CSV) ==="
if command -v column >/dev/null 2>&1; then column -s, -t "$CSV"; else cat "$CSV"; fi

echo
echo "=== COMPARAÇÃO (req/s): Least Connections em relação ao Round Robin ==="
awk -F, 'NR > 1 { k = $2 " req / " $3 " conc"; v[$1, k] = $4; keys[k] = 1 }
  END {
    for (k in keys) {
      rr = v["round_robin", k]; lc = v["least_conn", k]
      if (rr + 0 > 0 && lc + 0 > 0)
        printf "  %-22s RR=%9.2f  LC=%9.2f  diferença: %+.1f%%\n", k, rr, lc, (lc - rr) / rr * 100
    }
  }' "$CSV" | sort -n
echo
echo "Arquivos brutos do ab em: $RESULTS/ab/"
