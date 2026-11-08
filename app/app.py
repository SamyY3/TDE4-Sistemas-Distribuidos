"""Aplicação web Flask do projeto de balanceamento de carga.

Cada instância é identificada por um ID (1, 2, 3...). O ID define o nome,
a porta e a cor da instância, lidos de config/servers.json. Assim, o mesmo
código pode ser executado várias vezes, uma para cada servidor.

Exemplos:
    python app/app.py --id 1
    python app/app.py --id 2
    python app/app.py --id 3 --port 6003

Também é possível usar variáveis de ambiente (SERVER_ID, PORT, HOST).
"""

import argparse
import json
import os
import socket
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

from flask import Flask, jsonify, render_template

BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR.parent / "config" / "servers.json"


def load_servers():
    """Lê a lista de servidores do arquivo de configuração."""
    with open(CONFIG_PATH, encoding="utf-8") as f:
        return {s["id"]: s for s in json.load(f)["servers"]}


def create_app(server):
    """Cria a aplicação Flask para uma instância específica."""
    app = Flask(__name__)

    started_at = time.time()
    counter = {"requests": 0}
    lock = threading.Lock()

    def identity():
        """Dados que identificam esta instância."""
        return {
            "server_id": server["id"],
            "server_name": server["name"],
            "port": server["port"],
            "color": server["color"],
            "hostname": socket.gethostname(),
            "pid": os.getpid(),
        }

    @app.route("/")
    def index():
        with lock:
            counter["requests"] += 1
            total = counter["requests"]
        return render_template(
            "index.html",
            **identity(),
            total_requests=total,
            uptime=int(time.time() - started_at),
            now=datetime.now().strftime("%d/%m/%Y %H:%M:%S"),
        )

    @app.route("/health")
    def health():
        """Verificação de saúde (usada futuramente pelo balanceador)."""
        return jsonify(status="ok", **identity())

    @app.route("/info")
    def info():
        """Informações da instância em JSON."""
        with lock:
            total = counter["requests"]
        return jsonify(
            **identity(),
            total_requests=total,
            uptime_seconds=int(time.time() - started_at),
        )

    @app.after_request
    def add_server_header(response):
        """Informa em todo response qual servidor atendeu a requisição."""
        response.headers["X-Server-ID"] = str(server["id"])
        response.headers["X-Server-Name"] = server["name"]
        return response

    return app


def parse_args():
    parser = argparse.ArgumentParser(description="Instância do site Flask")
    parser.add_argument(
        "--id",
        type=int,
        default=int(os.environ.get("SERVER_ID", 1)),
        help="ID da instância, conforme config/servers.json (padrão: 1)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=os.environ.get("PORT"),
        help="Porta (padrão: a definida em config/servers.json)",
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("HOST"),
        help="Endereço de escuta (padrão: o definido em config/servers.json)",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    servers = load_servers()

    if args.id not in servers:
        ids = ", ".join(str(i) for i in sorted(servers))
        sys.exit(f"Erro: ID {args.id} não existe em servers.json. IDs válidos: {ids}")

    server = dict(servers[args.id])
    if args.port:
        server["port"] = int(args.port)
    host = args.host or server["host"]

    app = create_app(server)
    print(f"{server['name']} (ID {server['id']}) em http://{host}:{server['port']}")
    app.run(host=host, port=server["port"], debug=False, threaded=True)


if __name__ == "__main__":
    main()
