# Resultados e evidências para apresentação

## Resultados principais

- **Distribuição normal:** Round Robin distribuiu 9 requisições sequenciais na
  ordem `1 2 3 1 2 3 1 2 3`. Com Apache Benchmark em servidores equivalentes,
  ambos os algoritmos distribuíram aproximadamente um terço das requisições
  para cada servidor.
- **Servidor ocupado:** com uma requisição `/slow` em andamento, Round Robin
  enviou 3 de 9 requisições rápidas ao servidor ocupado; Least Connections
  enviou 0 de 9.
- **Tolerância a falhas:** com 3, 2 ou 1 servidor ativo, todas as chamadas
  retornaram HTTP 200; sem servidores, todas retornaram HTTP 502; após religar
  as instâncias, o serviço retornou a HTTP 200. Foram 10 cenários aprovados,
  cinco por algoritmo.
- **Carga:** todas as 12 medições de `ab` tiveram zero falhas e zero respostas
  não-2xx. Com servidores iguais, os resultados foram próximos. Com um servidor
  100 ms mais lento, Least Connections evitou parte da carga nesse servidor,
  mas não teve maior vazão nas três cargas.

As medições foram feitas uma vez por combinação em uma única máquina; servem
como demonstração e comparação indicativa, não como benchmark estatístico ou
previsão de capacidade de produção.

## Evidências salvas

| Arquivo | O que demonstra |
|---|---|
| `evidencia_distribuicao.txt` | Ordem observada nas nove requisições Round Robin |
| `evidencia_demo_algoritmos.txt` | Comparação Round Robin × Least Connections, inclusive com servidor ocupado |
| `evidencia_access_log.txt` | Requisições, status HTTP, servidor atendente e upstream registrados pelo Nginx |
| `falhas_20261111_112031.txt` | Cinco cenários de tolerância a falhas para cada algoritmo |
| `resumo_ab.csv` | Métricas do teste de carga com servidores iguais |
| `resumo_ab_servidor_lento.csv` | Métricas com atraso artificial de 100 ms no servidor 1 |
| `ab/` | Saídas completas do Apache Benchmark para cada combinação |
| `interpretacao_ab.md` | Explicação das métricas, resultados e limitações |

O resultado do teste de distribuição, as demonstrações e o log foram
capturados com os três servidores ativos. O algoritmo foi restaurado para
Round Robin após a captura.

## Roteiro curto para apresentar

1. Abra `http://127.0.0.1:8080/` e mostre a identificação da instância.
2. Mostre `evidencia_distribuicao.txt` e depois `evidencia_access_log.txt`:
   cabeçalho `X-Server-ID` e log comprovam qual servidor respondeu.
3. Use `evidencia_demo_algoritmos.txt` para explicar como o Least Connections
   evita a instância ocupada, diferentemente do Round Robin.
4. Mostre o relatório de falhas para comprovar o HTTP 502 na indisponibilidade
   total e a recuperação posterior.
5. Apresente as tabelas do README ou os CSVs e destaque que o Least Connections
   não ganhou em todas as cargas.

