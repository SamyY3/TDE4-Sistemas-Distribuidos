# Interpretação dos testes de carga

Testes executados em 11/11/2026 com Apache Benchmark 2.3, Nginx 1.28.3,
Python 3.14.4 e Ubuntu 26.04.1 LTS no WSL2. Todos os componentes foram
executados na mesma máquina. Cada combinação foi medida uma vez; portanto,
os resultados são indicativos e não demonstram significância estatística.

Os CSVs `resumo_ab.csv` e `resumo_ab_servidor_lento.csv` preservam somente
dados tabulares para continuarem compatíveis com os scripts do projeto. Este
arquivo explica como interpretar essas medições.

## Métricas

- **Req/s:** quantidade de requisições concluídas por segundo; maior tende a
  indicar maior vazão.
- **Tempo médio:** duração média das requisições; menor tende a ser melhor.
- **p95:** 95% das requisições terminaram dentro desse tempo; menor indica
  melhor latência na cauda.
- **Servidor 1/2/3:** número de requisições atendidas por cada instância.
- **Falhas / Não-2xx:** devem ser zero para uma execução sem erros; foram zero
  em todas as medições deste relatório.

## Servidores sem atraso artificial

| Carga | Req/s: Round Robin | Req/s: Least Connections | Diferença de vazão (LC vs. RR) |
|---|---:|---:|---:|
| 100 requisições / concorrência 10 | 988,22 | 993,22 | +0,5% |
| 1.000 requisições / concorrência 50 | 1.222,59 | 1.127,76 | -7,8% |
| 5.000 requisições / concorrência 100 | 1.200,45 | 1.218,93 | +1,5% |

Com servidores equivalentes, a vazão ficou próxima. Nenhum algoritmo venceu
em todas as cargas: Least Connections teve pequena vantagem em 100 e 5.000
requisições, enquanto Round Robin foi melhor em 1.000. As diferenças são
pequenas ou variáveis e não justificam concluir que um algoritmo é sempre
mais rápido nesse cenário. A distribuição também ficou aproximadamente
equilibrada entre as três instâncias.

## Servidor 1 com atraso artificial de 100 ms

| Carga | Req/s: Round Robin | Req/s: Least Connections | Diferença de vazão (LC vs. RR) |
|---|---:|---:|---:|
| 100 requisições / concorrência 10 | 175,74 | 460,70 | +162,1% |
| 1.000 requisições / concorrência 50 | 1.055,77 | 1.003,77 | -4,9% |
| 5.000 requisições / concorrência 100 | 1.146,73 | 979,37 | -14,6% |

Na carga menor, Least Connections evitou boa parte das requisições para o
servidor lento (5, contra 34 no Round Robin) e teve maior vazão e menor tempo
médio. Nas cargas maiores, também direcionou menos requisições ao servidor 1
(128 e 965, contra 333 e 1.667), mas isso não se traduziu em maior vazão nem
em menor latência: Round Robin teve melhores req/s, tempo médio e p95 nessas
duas medições.

Least Connections escolhe com base no número de conexões ativas, não na
velocidade ou capacidade real de cada instância. Ele reduz a pressão sobre
uma instância ocupada, mas não garante o melhor resultado global. Como Nginx,
gerador de carga e Flask compartilham a mesma máquina, o custo de CPU e a
concorrência também influenciam os números.

## Conclusão e limites

Os resultados ilustram que Least Connections pode ajudar quando há uma
requisição lenta e concorrência limitada, mas não garante melhor desempenho
sob todas as cargas. Para uma comparação mais robusta, execute cada combinação
várias vezes, alterne a ordem dos algoritmos, compare medianas e mantenha
máquina e condições de teste constantes. Os resultados medem este ambiente
local e não devem ser tratados como capacidade de produção.
