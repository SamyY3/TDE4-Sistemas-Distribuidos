# Roteiro de apresentação

Duração sugerida: **12 a 15 minutos** (8 a 10 de apresentação e demonstração, 4 a 5 de perguntas). Ajuste ao tempo do professor.

## Antes de começar (checklist)

- [ ] Nginx do sistema parado (`sudo systemctl stop nginx`); porta 8080 livre.
- [ ] Ambiente virtual ativo (`source venv/bin/activate`) na pasta do projeto.
- [ ] Três terminais abertos: **(1)** comandos, **(2)** `tail -f run/nginx/logs/access.log`, **(3)** reserva.
- [ ] Navegador com `http://127.0.0.1:8080` aberto.
- [x] Resultados reais gerados em `resultados/` e tabelas do README preenchidas.
- [x] Evidências capturadas: `resultados/evidencia_distribuicao.txt`, `evidencia_demo_algoritmos.txt`, `evidencia_access_log.txt` e `falhas_20261111_112031.txt`.
- [ ] Ensaio feito uma vez antes. Plano B se a demonstração falhar: mostrar os arquivos de `resultados/` e a página de resumo `resultados/evidencias_apresentacao.md`.

## Estrutura da apresentação

| Tempo | Parte | O que dizer / mostrar |
|---|---|---|
| 1 min | **Abertura** | Tema, objetivo e o que será demonstrado: 3 servidores, Nginx, 2 algoritmos, falhas e carga |
| 2 min | **Problema e conceito** | Um único servidor limita desempenho e disponibilidade. O balanceador distribui as requisições entre vários servidores e esconde falhas |
| 2 min | **Arquitetura** | Mostrar o diagrama do README (seção 2): cliente → Nginx (:8080) → servidores 1, 2 e 3 (:5001–5003). Cada servidor se identifica por nome, cor e cabeçalho `X-Server-ID` |
| 2 min | **Algoritmos** | Round Robin (em sequência, ignora a carga) × Least Connections (menos conexões ativas, se adapta). Quando cada um é indicado (README, seção 4) |
| 4 min | **Demonstração ao vivo** | Roteiro abaixo |
| 2 min | **Resultados** | Tabelas da seção 10 do README: o que mudou entre os algoritmos e por quê |
| 1 min | **Conclusão** | O que foi aprendido e as limitações (README, seções 12 e 13) |

## Roteiro da demonstração

**1. Subir o ambiente**

```bash
bash scripts/start_servers.sh
bash scripts/start_nginx.sh
```

**2. Mostrar a distribuição (Round Robin)**

- No navegador, atualizar a página 6 vezes: nome e cor mudam (lavanda, Xanadu e Lavender Purple).
- No terminal:

```bash
for i in $(seq 1 9); do curl -s -o /dev/null -D - http://127.0.0.1:8080/ | grep -i x-server-id; done
```

- Apontar o terminal 2: cada linha do log mostra `servidor=<id>`.

**3. Mostrar a diferença entre os algoritmos**

```bash
bash scripts/demo_algoritmos.sh
```

Explicar a saída: no Teste B, um servidor está ocupado com uma requisição lenta. O Round Robin continua enviando a ele sua fatia; o Least Connections o evita.

Evidência salva: `resultados/evidencia_demo_algoritmos.txt`. A ordem e os cabeçalhos capturados estão em `resultados/evidencia_distribuicao.txt`; o log correspondente está em `resultados/evidencia_access_log.txt`.

**4. Simular falhas**

```bash
bash scripts/server_ctl.sh stop 2       # recarregar o navegador: continua funcionando
bash scripts/server_ctl.sh stop 3       # só o servidor 1 responde
bash scripts/server_ctl.sh stop 1       # nenhum servidor: o Nginx responde 502
bash scripts/server_ctl.sh start 1      # religar
bash scripts/server_ctl.sh start 2
bash scripts/server_ctl.sh start 3      # aguardar até 5 s (fail_timeout) para voltarem ao rodízio
```

**5. Carga (rápida; os números completos já estão nas tabelas)**

```bash
CASOS="1000:50" bash scripts/run_ab.sh
```

**6. Encerrar**

```bash
bash scripts/stop_nginx.sh
bash scripts/stop_servers.sh
```

## Perguntas prováveis e respostas

**Por que o Least Connections nem sempre é mais rápido?**
Com servidores iguais e requisições curtas, quase sempre há empate de conexões e ele se comporta como o Round Robin. A vantagem aparece quando a duração das requisições varia ou um servidor é mais lento.

**O que acontece quando um servidor cai?**
O Nginx tenta a mesma requisição em outra instância (`proxy_next_upstream`) e deixa a que falhou fora do rodízio por 5 s (`max_fails=1 fail_timeout=5s`). O cliente não percebe, desde que reste uma instância. Sem nenhuma, recebe 502.

**O Nginx não é um ponto único de falha?**
Sim. O balanceador elimina a dependência de um servidor de aplicação, mas ele próprio precisa de redundância em produção (por exemplo, dois balanceadores com IP virtual).

**O Nginx verifica a saúde dos servidores?**
Apenas de forma passiva: percebe a falha quando uma requisição real falha. A verificação ativa (consultas periódicas a `/health`) é recurso do Nginx Plus.

**Por que `worker_processes 1`?**
Sem memória compartilhada, cada worker conta só as próprias conexões; com um worker, o Least Connections vê todas as conexões ativas.

**Como o servidor que respondeu é identificado?**
Pelo nome e cor na página, pelo cabeçalho `X-Server-ID` e pelo log do Nginx (`servidor=<id>`).

**Os resultados do `ab` são confiáveis?**
São confiáveis para comparar os algoritmos entre si no mesmo ambiente. Nginx, servidores e `ab` rodam na mesma máquina e disputam CPU, então os valores absolutos dependem do hardware.

**E as sessões de usuário?**
O balanceamento não tem afinidade de sessão e as instâncias não compartilham estado (o contador de requisições é por instância). Para sessões, seria preciso um armazenamento compartilhado ou *sticky sessions*.

**O que usaria em produção?**
Um servidor WSGI (como o Gunicorn) no lugar do servidor de desenvolvimento do Flask, mais de um balanceador e verificação de saúde ativa.
