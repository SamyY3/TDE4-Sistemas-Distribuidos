#!/usr/bin/env bash
# Converte o CSV gerado por run_ab.sh em uma tabela Markdown, pronta para colar no README.
# Uso: scripts/gerar_tabela.sh [arquivo.csv]   (padrão: resultados/resumo_ab.csv)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSV="${1:-$ROOT/resultados/resumo_ab.csv}"

if [ ! -f "$CSV" ]; then
  echo "ERRO: arquivo não encontrado: $CSV (rode scripts/run_ab.sh antes)" >&2
  exit 1
fi

awk -F, '
  NR == 1 {
    print "| Algoritmo | Requisições | Concorrência | Req/s | Tempo médio (ms) | p95 (ms) | Falhas | Não-2xx | Servidor 1 | Servidor 2 | Servidor 3 |"
    print "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    next
  }
  {
    nome = ($1 == "round_robin") ? "Round Robin" : (($1 == "least_conn") ? "Least Connections" : $1)
    printf "| %s |", nome
    for (i = 2; i <= NF; i++) printf " %s |", $i
    printf "\n"
  }' "$CSV"
