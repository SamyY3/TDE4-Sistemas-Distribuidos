# Balanceador de Carga com Nginx e Flask

Projeto acadêmico que demonstra o balanceamento de carga entre **três instâncias independentes** de uma aplicação web (Python/Flask) usando o **Nginx** como balanceador, comparando os algoritmos **Round Robin** e **Least Connections**, a tolerância a falhas e o desempenho sob carga com o **Apache Benchmark (`ab`)**.

> **Estado dos resultados:** as seções [Resultados](#10-resultados) e [Conclusão](#12-conclusão) estão preenchidas com as medições realizadas. As evidências e a interpretação estão em `resultados/`; os números são específicos deste ambiente e devem ser tratados como comparação indicativa.

## Sumário

1. [Visão geral](#1-visão-geral)
2. [Arquitetura](#2-arquitetura)
3. [Estrutura do projeto](#3-estrutura-do-projeto)
4. [Algoritmos de balanceamento](#4-algoritmos-de-balanceamento)
5. [Requisitos e instalação](#5-requisitos-e-instalação)
6. [Execução](#6-execução)
7. [Alternar o algoritmo](#7-alternar-o-algoritmo)
8. [Simulação de falhas](#8-simulação-de-falhas)
9. [Testes de carga com Apache Benchmark](#9-testes-de-carga-com-apache-benchmark)
10. [Resultados](#10-resultados)
11. [Evidências dos testes](#11-evidências-dos-testes)
12. [Conclusão](#12-conclusão)
13. [Limitações](#13-limitações)
14. [Solução de problemas](#14-solução-de-problemas)
15. [Referência dos scripts](#15-referência-dos-scripts)
16. [Histórico de commits](#16-histórico-de-commits)

---

## 1. Visão geral

| Item | Descrição |
|---|---|
| Aplicação | Site em Flask que mostra qual servidor o atendeu |
| Instâncias | 3 processos independentes (portas 5001, 5002 e 5003) |
| Balanceador | Nginx na porta 8080 |
| Algoritmos | Round Robin e Least Connections (alternáveis por script) |
| Falhas | Reenvio automático da requisição a outra instância; 502 se todas caírem |
| Carga | Apache Benchmark com várias combinações de requisições e concorrência |

## 2. Arquitetura

```
                          +------------------+        +----------------------+
                          |                  | -----> | Servidor 1  (:5001)  |
  Cliente (navegador,     |      Nginx       |        +----------------------+
  curl, ab)               |   balanceador    | -----> | Servidor 2  (:5002)  |
  ------------------->    |     (:8080)      |        +----------------------+
  http://127.0.0.1:8080   |                  | -----> | Servidor 3  (:5003)  |
                          +------------------+        +----------------------+
                           escolhe a instância         mesma aplicação Flask,
                           (Round Robin ou             executada 3 vezes com
                           Least Connections)          --id 1, --id 2 e --id 3
```

**Fluxo de uma requisição**

1. O cliente envia a requisição ao Nginx (`:8080`).
2. O Nginx escolhe uma instância conforme o algoritmo ativo (grupo `app_servers`).
3. A instância responde, incluindo os cabeçalhos `X-Server-ID` e `X-Server-Name`.
4. O Nginx devolve a resposta ao cliente e acrescenta o cabeçalho `X-Upstream` (endereço da instância usada).
5. O log de acessos do Nginx registra `servidor=<id>` e `upstream=<endereço>` de cada requisição.

**Identificação de qual servidor respondeu** (três formas):

- Na página: o nome e a cor do servidor mudam (azul, verde e laranja).
- Nos cabeçalhos HTTP: `X-Server-ID` e `X-Server-Name`.
- No log: `run/nginx/logs/access.log`.

**Aplicação Flask** (`app/app.py`): cada instância lê seu nome, porta e cor de `config/servers.json` a partir do `--id`.

| Rota | Função |
|---|---|
| `/` | Página inicial com os dados do servidor e o contador de requisições |
| `/health` | Verificação de saúde em JSON (sem latência artificial) |
| `/info` | Dados da instância em JSON (inclui `delay_ms`) |
| `/slow?s=N` | Responde após N segundos (máx. 30); usada para demonstrar o Least Connections |

**Tolerância a falhas** (`nginx/nginx.conf` e `nginx/algorithms/*.conf`):

- `proxy_next_upstream error timeout` e `proxy_next_upstream_tries 3`: se uma instância recusar a conexão ou estourar o tempo, a mesma requisição é reenviada a outra.
- `max_fails=1 fail_timeout=5s`: após uma falha, a instância fica fora do rodízio por 5 s e depois é testada de novo.
- Se todas as instâncias falharem, o cliente recebe **502 Bad Gateway**.

## 3. Estrutura do projeto

```
balanceador-carga/
├── README.md
├── requirements.txt              # Flask
├── .gitignore
├── .gitattributes                # força finais de linha LF (necessário no Windows/WSL)
├── app/
│   ├── app.py                    # aplicação Flask (uma instância por --id)
│   ├── templates/index.html
│   └── static/css/style.css
├── config/
│   └── servers.json              # id, nome, host, porta e cor de cada instância
├── nginx/
│   ├── nginx.conf                # configuração do balanceador
│   └── algorithms/
│       ├── round_robin.conf      # grupo upstream com Round Robin
│       └── least_conn.conf       # grupo upstream com Least Connections
├── scripts/                      # veja a seção 15
├── docs/
│   └── roteiro_apresentacao.md
└── resultados/                   # gerado pelos testes (relatórios, CSV, saídas do ab)
```

Arquivos gerados durante a execução (ignorados pelo Git): `run/` (PIDs, logs das instâncias, logs e temporários do Nginx) e `nginx/upstream.active.conf` (algoritmo ativo).

## 4. Algoritmos de balanceamento

### Round Robin

Distribui as requisições **em sequência**: 1, 2, 3, 1, 2, 3... É o padrão do Nginx.

- **Vantagens:** simples, previsível, sem custo de controle.
- **Limitação:** ignora a carga atual dos servidores. Se um servidor estiver ocupado ou for mais lento, continua recebendo a mesma fatia das requisições.
- **Indicado quando:** os servidores são equivalentes e as requisições têm duração parecida.

### Least Connections (`least_conn`)

Envia cada requisição ao servidor com **menos conexões ativas** naquele momento. Em caso de empate, alterna entre os empatados.

- **Vantagens:** se adapta a requisições de duração variável e a servidores com capacidades diferentes.
- **Limitação:** com requisições curtas e sem concorrência, quase sempre há empate e o comportamento se aproxima do Round Robin.
- **Indicado quando:** a duração das requisições varia muito ou os servidores não têm o mesmo desempenho.

> **Por que `worker_processes 1`?** Sem memória compartilhada (`zone`), cada worker do Nginx conta apenas as próprias conexões. Com um único worker, o Least Connections enxerga todas as conexões ativas. Não altere esse valor sem considerar isso.

## 5. Requisitos e instalação

**Requisitos**

- Linux, macOS ou WSL (no Windows 11, use **Ubuntu no WSL**). Os scripts são em Bash: execute sempre com `bash scripts/<nome>.sh`.
- Python 3.9 ou superior.
- Nginx.
- Apache Benchmark (`ab`), apenas para os testes de carga.
- `curl`.

**Instalação (Debian/Ubuntu/WSL)**

```bash
sudo apt update
sudo apt install nginx apache2-utils curl python3 python3-venv

cd balanceador-carga
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

O projeto usa o **próprio** Nginx, na porta **8080**; o serviço `nginx` instalado pelo `apt` (porta 80) não atrapalha e não precisa ser parado. O venv também é opcional na hora de executar: se existir uma pasta `venv/` ou `.venv/` no projeto, os scripts a usam automaticamente.

**Windows 11 com WSL (Ubuntu): cuidados**

- **Mantenha o projeto dentro do sistema de arquivos do Linux** (por exemplo, `~/balanceador-carga`), e não em `/mnt/c/...`. Na pasta do Windows, a partida das instâncias fica lenta e as permissões dos arquivos se comportam de forma diferente.
- **Clone o repositório dentro do WSL** (`git clone ...` no terminal do Ubuntu). Se clonar pelo Git do Windows, o arquivo `.gitattributes` do projeto força o final de linha **LF** nos scripts; sem isso, o Git do Windows os converteria para CRLF e o Bash falharia com erros como `set: pipefail: invalid option name` ou `$'\r': command not found`.
- O navegador do Windows acessa o balanceador normalmente em `http://localhost:8080`.
- Em versões do WSL sem `systemd`, comandos como `systemctl` não funcionam; este projeto não precisa deles.

No macOS, instale `nginx` e `httpd` (que traz o `ab`) com o Homebrew.

## 6. Execução

Na pasta do projeto:

```bash
bash scripts/start_servers.sh     # sobe as 3 instâncias (5001, 5002, 5003)
bash scripts/start_nginx.sh       # valida a configuração e sobe o Nginx (8080)
```

Cada instância só é dada como iniciada depois que o `/health` responde **com o PID dela**; se a porta estiver ocupada por outro programa ou o Flask não estiver instalado, o script mostra o erro e as últimas linhas do log da instância.

Acesse **http://127.0.0.1:8080** e atualize a página várias vezes: o nome e a cor do servidor mudam (o pedido de `/favicon.ico` do navegador é respondido pelo próprio Nginx, para não consumir uma vez do rodízio). Pelo terminal:

```bash
curl -i http://127.0.0.1:8080/                        # veja X-Server-ID e X-Upstream
for i in $(seq 1 9); do
  curl -s -o /dev/null -D - http://127.0.0.1:8080/ | grep -i x-server-id
done
tail -f run/nginx/logs/access.log                     # log com servidor=<id>
```

Para encerrar:

```bash
bash scripts/stop_nginx.sh
bash scripts/stop_servers.sh
```

Uma instância isolada também pode ser executada sem o Nginx: `python app/app.py --id 1` (opcionais: `--port`, `--host`, `--delay-ms`).

## 7. Alternar o algoritmo

```bash
bash scripts/set_algorithm.sh round_robin
bash scripts/set_algorithm.sh least_conn
```

O script copia a configuração escolhida (`nginx/algorithms/`) para `nginx/upstream.active.conf` e, se o Nginx estiver rodando, valida e **recarrega** a configuração sem derrubá-lo. Sem nenhuma escolha prévia, o `start_nginx.sh` usa Round Robin.

Para **demonstrar a diferença** entre os dois algoritmos:

```bash
bash scripts/demo_algoritmos.sh
```

O script faz, para cada algoritmo, (A) 9 requisições em sequência e (B) deixa um servidor ocupado com uma requisição `/slow` de 4 s e envia 9 requisições rápidas, contando quantas caíram no servidor ocupado.

## 8. Simulação de falhas

### Manual

```bash
bash scripts/server_ctl.sh stop 2      # desliga só o servidor 2
curl -i http://127.0.0.1:8080/         # continua respondendo, sem usar o servidor 2
bash scripts/server_ctl.sh start 2     # religa (volta ao rodízio após até 5 s)
```

### Automática

```bash
bash scripts/test_falhas.sh            # REQS=50 para mais requisições por cenário
```

Para cada algoritmo, o script executa os cenários abaixo, confere o resultado (`[OK]` ou `[FALHA]`), salva o relatório em `resultados/falhas_<data>.txt` e, ao final, religa os três servidores. O código de saída é 0 se tudo passou e 1 caso contrário.

| # | Cenário | Resultado esperado |
|---|---|---|
| 1 | 3 servidores ativos | Todas as respostas 200, distribuídas entre os servidores 1, 2 e 3 |
| 2 | 2 servidores ativos (servidor 1 desligado) | Todas 200, apenas servidores 2 e 3 |
| 3 | 1 servidor ativo (apenas o 3) | Todas 200, apenas servidor 3 |
| 4 | Nenhum servidor ativo | Todas as respostas exatamente **HTTP 502** e nenhuma instância identificada (qualquer outro código, como 500, 503, 504 ou 000, reprova o teste) |
| 5 | Recuperação (todos religados) | Todas 200, os três servidores voltam a responder |

## 9. Testes de carga com Apache Benchmark

```bash
bash scripts/run_ab.sh
```

Por padrão, executa as combinações `100:10`, `1000:50` e `5000:100` (requisições:concorrência) para os dois algoritmos, usando `ab -l -n <N> -c <C>` (`-l` aceita respostas de tamanho variável, pois a página muda a cada requisição).

| Variável | Função | Exemplo |
|---|---|---|
| `CASOS` | Combinações requisições:concorrência | `CASOS="200:20 2000:100"` |
| `ALGOS` | Algoritmos testados | `ALGOS=least_conn` |
| `CAMINHO` | Caminho testado | `CAMINHO="/slow?s=0.05"` |
| `TAG` | Sufixo dos arquivos (separa cenários) | `TAG=servidor_lento` |
| `URL` | Endereço do balanceador | `URL=http://127.0.0.1:8080` |

**Saídas** (pasta `resultados/`): `ab/<algoritmo>_n<N>_c<C>[_<TAG>].txt` (saída completa do `ab`), `resumo_ab[_<TAG>].csv` (tabela-resumo) e, no terminal, a comparação em % entre os algoritmos.

**Verificações do script.** Antes de começar, o `run_ab.sh` recusa-se a rodar (código de saída 1) se o `ab` não estiver instalado, se o balanceador não responder ou se alguma das 3 instâncias estiver fora do ar, pois isso falsearia a comparação. Durante os testes, ele registra um **AVISO** (e termina com código de saída **2**) quando o `ab` falha, quando há requisições falhadas ou respostas fora da faixa 2xx, ou quando o log do Nginx não soma o número de requisições enviadas. Com avisos, **confira o resultado antes de usar os números**.

**Métricas do CSV**

| Coluna | Significado |
|---|---|
| `req_por_seg` | Requisições por segundo (maior é melhor) |
| `tempo_medio_ms` | Tempo médio por requisição, em ms (menor é melhor) |
| `p95_ms` | 95% das requisições terminaram em até esse tempo |
| `falhas` / `nao_2xx` | Falhas reportadas pelo `ab` / respostas fora da faixa 2xx |
| `servidor1/2/3` | Quantas requisições cada servidor atendeu (lido do log do Nginx) |

### Dois cenários recomendados

**A) Servidores idênticos** (comportamento padrão):

```bash
bash scripts/run_ab.sh
```

**B) Um servidor mais lento** (onde o Least Connections tende a se diferenciar):

```bash
bash scripts/stop_servers.sh
DELAY_MS_1=100 bash scripts/start_servers.sh     # servidor 1 com +100 ms por resposta
TAG=servidor_lento bash scripts/run_ab.sh
```

Depois do cenário B, volte ao normal com `bash scripts/stop_servers.sh && bash scripts/start_servers.sh`.

## 10. Resultados

> Os valores desta seção devem vir **exclusivamente** dos arquivos gerados em `resultados/` na máquina em que os testes forem executados. Os resultados de carga dependem do hardware e do que mais estiver rodando; use-os para comparar os algoritmos entre si, não como medida absoluta.

### Como preencher os resultados

```bash
bash scripts/gerar_tabela.sh                                  # lê resultados/resumo_ab.csv
bash scripts/gerar_tabela.sh resultados/resumo_ab_servidor_lento.csv
```

O script imprime uma tabela em Markdown. Os resultados medidos em 11/11/2026 estão preenchidos abaixo; a análise e as limitações das medições estão em [resultados/interpretacao_ab.md](resultados/interpretacao_ab.md). Ambiente registrado:

- Máquina / CPU / memória: **não registrados**
- Sistema operacional: Windows 11 com Ubuntu 26.04.1 LTS no WSL2
- Versões: Nginx 1.28.3, Apache Benchmark 2.3, Python 3.14.4
- Data dos testes: 11/11/2026

### 10.1 Carga: servidores idênticos

| Algoritmo | Requisições | Concorrência | Req/s | Tempo médio (ms) | p95 (ms) | Falhas | Não-2xx | Servidor 1 | Servidor 2 | Servidor 3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Round Robin | 100 | 10 | 988.22 | 10.119 | 13 | 0 | 0 | 34 | 33 | 33 |
| Least Connections | 100 | 10 | 993.22 | 10.068 | 13 | 0 | 0 | 34 | 32 | 34 |
| Round Robin | 1000 | 50 | 1222.59 | 40.897 | 50 | 0 | 0 | 333 | 334 | 333 |
| Least Connections | 1000 | 50 | 1127.76 | 44.336 | 58 | 0 | 0 | 341 | 331 | 328 |
| Round Robin | 5000 | 100 | 1200.45 | 83.302 | 103 | 0 | 0 | 1667 | 1666 | 1667 |
| Least Connections | 5000 | 100 | 1218.93 | 82.039 | 98 | 0 | 0 | 1670 | 1663 | 1667 |

### 10.2 Carga: servidor 1 com +100 ms de latência

| Algoritmo | Requisições | Concorrência | Req/s | Tempo médio (ms) | p95 (ms) | Falhas | Não-2xx | Servidor 1 | Servidor 2 | Servidor 3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Round Robin | 100 | 10 | 175.74 | 56.903 | 106 | 0 | 0 | 34 | 33 | 33 |
| Least Connections | 100 | 10 | 460.70 | 21.706 | 103 | 0 | 0 | 5 | 50 | 45 |
| Round Robin | 1000 | 50 | 1055.77 | 47.359 | 113 | 0 | 0 | 333 | 334 | 333 |
| Least Connections | 1000 | 50 | 1003.77 | 49.812 | 117 | 0 | 0 | 128 | 437 | 435 |
| Round Robin | 5000 | 100 | 1146.73 | 87.204 | 165 | 0 | 0 | 1667 | 1666 | 1667 |
| Least Connections | 5000 | 100 | 979.37 | 102.106 | 181 | 0 | 0 | 965 | 2015 | 2020 |

**Interpretação:** com servidores iguais, a vazão ficou próxima e nenhum algoritmo venceu em todas as cargas. Com o servidor 1 mais lento, Least Connections reduziu a quantidade de requisições enviadas a ele; isso melhorou a vazão na menor carga, mas não nas duas maiores. Consulte [a análise detalhada](resultados/interpretacao_ab.md) para interpretar as métricas e considerar as limitações de uma única execução por combinação.

### 10.3 Falhas

Resultado observado em `resultados/falhas_20261111_112031.txt` (9 requisições por cenário).

| # | Cenário | Round Robin (observado) | Least Connections (observado) |
|---|---|---|---|
| 1 | 3 servidores | 9/9 HTTP 200; 3 por servidor | 9/9 HTTP 200; 3 por servidor |
| 2 | 2 servidores | 9/9 HTTP 200; servidores 2 e 3 | 9/9 HTTP 200; servidores 2 e 3 |
| 3 | 1 servidor | 9/9 HTTP 200; servidor 3 | 9/9 HTTP 200; servidor 3 |
| 4 | Nenhum servidor | 9/9 HTTP 502 | 9/9 HTTP 502 |
| 5 | Recuperação | 9/9 HTTP 200; os três servidores | 9/9 HTTP 200; os três servidores |

Evidência: `resultados/falhas_20261111_112031.txt` (9 requisições por cenário).

### 10.4 Demonstração dos algoritmos (`demo_algoritmos.sh`)

| Algoritmo | Ordem em 9 requisições sequenciais | Requisições rápidas enviadas ao servidor ocupado (de 9) |
|---|---|---|
| Round Robin | 1 2 3 1 2 3 1 2 3 | 3 |
| Least Connections | 1 2 3 1 2 3 1 2 3 | 0 |

**Explicação:** em sequência e sem carga concorrente, os dois algoritmos se comportam de forma semelhante. Quando uma requisição `/slow` mantém uma conexão aberta, Least Connections evita o servidor ocupado; Round Robin continua a distribuição cíclica.

## 11. Evidências dos testes

Os testes geram evidências verificáveis; mantenha-as no repositório (pasta `resultados/`):

| Evidência | Arquivo / comando |
|---|---|
| Relatório do teste de falhas | `resultados/falhas_<data>.txt` |
| Saída completa de cada execução do `ab` | `resultados/ab/*.txt` |
| Tabela-resumo das cargas | `resultados/resumo_ab*.csv` |
| Explicação e interpretação dos resultados | `resultados/interpretacao_ab.md` |
| Trecho capturado do log do Nginx | `resultados/evidencia_access_log.txt` |
| Ordem observada nas requisições Round Robin | `resultados/evidencia_distribuicao.txt` |
| Demonstração dos algoritmos | `resultados/evidencia_demo_algoritmos.txt` |
| Resumo para apresentação | `resultados/evidencias_apresentacao.md` |

As evidências acima foram geradas durante os testes e estão prontas para consulta. Para atualizá-las, com os três servidores e o Nginx ativos, execute:

```bash
bash scripts/demo_algoritmos.sh | tee resultados/evidencia_demo_algoritmos.txt
grep -m 1 'Ordem dos servidores:' resultados/evidencia_demo_algoritmos.txt > resultados/evidencia_distribuicao.txt
tail -n 30 run/nginx/logs/access.log > resultados/evidencia_access_log.txt
```

Veja o roteiro resumido em [resultados/evidencias_apresentacao.md](resultados/evidencias_apresentacao.md).

Uma captura da página no navegador pode complementar a apresentação; a paleta atual identifica os servidores em lavanda, Xanadu e Lavender Purple.

## 12. Conclusão

### O que o projeto demonstra

- Uma mesma aplicação pode ser executada em várias instâncias independentes e identificada individualmente.
- O Nginx atua como ponto único de entrada e distribui as requisições entre as instâncias; trocar o algoritmo é uma mudança de configuração, sem alterar a aplicação.
- O **Round Robin** é simples e eficaz quando servidores e requisições são homogêneos, mas não considera a carga atual.
- O **Least Connections** considera as conexões ativas e tende a ser mais adequado quando a duração das requisições varia ou um servidor é mais lento.
- A **tolerância a falhas** vem do reenvio da requisição a outra instância e da retirada temporária da instância que falhou (verificação *passiva*). O Nginx de código aberto não faz verificação de saúde ativa.
- O próprio Nginx continua sendo um **ponto único de falha**: ele elimina a dependência de um servidor de aplicação, não a de um balanceador.

### Resultados observados

Com servidores idênticos, os resultados foram próximos e variaram por carga: Round Robin teve maior vazão em 1.000 requisições, enquanto Least Connections teve pequena vantagem em 100 e 5.000. Com o servidor 1 100 ms mais lento, Least Connections enviou menos requisições a ele e obteve maior vazão na carga de 100 requisições; nas cargas de 1.000 e 5.000, Round Robin apresentou maior vazão e menores tempos médio e p95. Portanto, Least Connections não é sempre mais rápido: ele considera conexões ativas, mas não mede diretamente a capacidade de cada servidor, e todos os processos compartilham a mesma máquina. As 12 medições não registraram falhas nem respostas fora de 2xx. Os cenários de indisponibilidade corresponderam ao esperado: 200 quando havia servidores disponíveis, 502 quando todos estavam parados e retorno a 200 após a recuperação. Cada carga foi executada uma vez, então uma comparação estatística exige repetições; veja [resultados/interpretacao_ab.md](resultados/interpretacao_ab.md).

## 13. Limitações

- Todos os componentes (Nginx, três instâncias e `ab`) rodam na **mesma máquina** e disputam CPU; os resultados servem para comparação relativa.
- O servidor embutido do Flask é de **desenvolvimento**. Em produção, usar um servidor WSGI (por exemplo, Gunicorn).
- O balanceamento é por conexão/requisição, sem afinidade de sessão (*sticky sessions*) e sem estado compartilhado entre as instâncias (o contador de requisições é por instância).
- As portas aparecem em `config/servers.json`, `nginx/algorithms/*.conf`, `scripts/start_servers.sh` e `scripts/server_ctl.sh`; ao alterá-las, mude em todos.

## 14. Solução de problemas

| Problema | Causa provável / solução |
|---|---|
| `nginx: command not found` | Instale o Nginx ou use `NGINX=/caminho/do/nginx bash scripts/start_nginx.sh` |
| `bind() to 0.0.0.0:8080 failed` | Porta 8080 em uso. Pare o outro processo (ou o serviço `nginx` do sistema) |
| `[alert] could not open error log file` | Aviso que pode aparecer ao executar o Nginx sem root: ele tenta abrir o log padrão do sistema antes de ler a configuração do projeto |
| Erro `502` mesmo com servidores ligados | Confira `bash scripts/start_servers.sh` e `run/logs/server<N>.log`; após religar, aguarde até 5 s (`fail_timeout`) |
| `ab: command not found` | `sudo apt install apache2-utils` |
| `Permission denied` ao executar scripts | Use `bash scripts/<nome>.sh` |
| `set: pipefail: invalid option name` ou `$'\r': command not found` | Os scripts estão com final de linha CRLF (comum ao clonar pelo Git do Windows). Clone dentro do WSL, ou converta: `sed -i 's/\r$//' scripts/*.sh` |
| `ERRO: Servidor N não iniciou` | Veja as linhas do log exibidas: porta ocupada por outro programa, Flask não instalado (`pip install -r requirements.txt`) ou venv errado |
| `ERRO: Nginx não encontrado` | `sudo apt install nginx` |
| `ERRO: nem todas as 3 instâncias respondem` (`run_ab.sh`) | Rode `bash scripts/start_servers.sh` antes dos testes de carga |
| `run_ab.sh` termina com código 2 e avisos | Há falhas, respostas não-2xx ou log incompleto: não use os números sem investigar |
| Projeto lento ou comportamento estranho no WSL | Mova o projeto de `/mnt/c/...` para dentro do Linux (`~/`) |
| Mudou o algoritmo e nada mudou | Confirme a mensagem "Nginx recarregado" de `set_algorithm.sh`; veja `nginx/upstream.active.conf` |

## 15. Referência dos scripts

| Script | Função |
|---|---|
| `scripts/start_servers.sh` / `stop_servers.sh` | Inicia / encerra as 3 instâncias |
| `scripts/server_ctl.sh start\|stop <1-3>` | Liga / desliga uma instância (simulação de falha). Aceita `DELAY_MS_<id>` |
| `scripts/start_nginx.sh` / `stop_nginx.sh` | Inicia / encerra o Nginx (porta 8080, sem root) |
| `scripts/set_algorithm.sh round_robin\|least_conn` | Alterna o algoritmo e recarrega o Nginx |
| `scripts/demo_algoritmos.sh` | Demonstra a diferença entre os algoritmos |
| `scripts/test_falhas.sh` | Teste automático de falhas (5 cenários × 2 algoritmos) |
| `scripts/run_ab.sh` | Testes de carga com `ab` (CSV e saídas em `resultados/`) |
| `scripts/gerar_tabela.sh` | Converte o CSV de resultados em tabela Markdown |
| `scripts/lib.sh` | Funções compartilhadas (não é executado diretamente) |

Variáveis de ambiente reconhecidas: `PYTHON` (se ausente, usa `venv/` ou `.venv/` do projeto e, por fim, `python3`), `NGINX`, `URL`, `REQS`, `ALGOS`, `CASOS`, `CAMINHO`, `TAG`, `RESULTS`, `ACCESS_LOG` e `DELAY_MS_1/2/3`.

## 16. Histórico de commits

| # | Mensagem | Conteúdo |
|---|---|---|
| 1 | `feat: cria estrutura inicial e interface do site` | Estrutura, aplicação Flask, interface, identificação do servidor, `requirements.txt` |
| 2 | `feat: implementa tres instancias e balanceador de carga` | Três instâncias, Nginx, Round Robin e Least Connections, alternância de algoritmo |
| 3 | `feat: adiciona testes de falhas e carga` | Simulação de falhas, `ab`, scripts de carga, registro dos resultados |
| 4 | `docs: finaliza documentacao e testes do projeto` | README, roteiro de apresentação, tabelas de resultados |
