#!/usr/bin/env python3
"""Serve uma release falsa do GitHub para exercitar os scripts de instalacao."""
import hashlib
import http.server
import json
import socketserver
import sys
import threading
import zipfile
from pathlib import Path

VERSAO = sys.argv[1] if len(sys.argv) > 1 else "9.9.9"
RAIZ = Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/oflow-fixture")
CORROMPER = len(sys.argv) > 3 and sys.argv[3] == "corromper"

RAIZ.mkdir(parents=True, exist_ok=True)


def montar_pacote(plataforma: str) -> Path:
    caminho = RAIZ / f"OFlow.Mother.v{VERSAO}-{plataforma}.zip"
    with zipfile.ZipFile(caminho, "w") as arquivo:
        arquivo.writestr("OFlow.Mother.exe", VERSAO)
        arquivo.writestr("OFlow.Mother", VERSAO)
        arquivo.writestr("appsettings.json", '{"Parametros":{"Gates":"https://api.octopustech.app"}}')
        arquivo.writestr("instalar-windows.ps1", "Write-Host 'instalador fixture'")
        arquivo.writestr("instalar-linux.sh", "#!/bin/sh\necho instalador fixture\n")
    return caminho


def montar_script(nome: str) -> Path:
    caminho = RAIZ / nome
    caminho.write_text(f'#!/usr/bin/env bash\nprintf "EXECUTADO {nome} ARGUMENTOS:%s\\n" "$*"\n')
    return caminho


pacotes = [montar_pacote("windows"), montar_pacote("linux"), montar_script("atualizar-producao.sh"), montar_script("instalar-producao.sh")]
linhas = []
for pacote in pacotes:
    soma = hashlib.sha256(pacote.read_bytes()).hexdigest()
    if CORROMPER:
        soma = "0" * 64
    linhas.append(f"{soma}  {pacote.name}")
(RAIZ / "SHA256SUMS.txt").write_text("\n".join(linhas) + "\n")

with socketserver.TCPServer(("127.0.0.1", 0), None) as sonda:
    PORTA = sonda.server_address[1]

BASE = f"http://127.0.0.1:{PORTA}"
release = {
    "tag_name": f"v{VERSAO}",
    "assets": [
        {"name": p.name, "browser_download_url": f"{BASE}/{p.name}", "size": p.stat().st_size}
        for p in pacotes
    ]
    + [{"name": "SHA256SUMS.txt", "browser_download_url": f"{BASE}/SHA256SUMS.txt", "size": 1}],
}


class Manipulador(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(RAIZ), **kwargs)

    def do_GET(self):
        if self.path.endswith("/releases/latest"):
            corpo = json.dumps(release).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(corpo)))
            self.end_headers()
            self.wfile.write(corpo)
            return
        super().do_GET()

    def log_message(self, *args):
        pass


servidor = socketserver.TCPServer(("127.0.0.1", PORTA), Manipulador)
threading.Thread(target=servidor.serve_forever, daemon=True).start()
print(BASE, flush=True)
try:
    threading.Event().wait()
except KeyboardInterrupt:
    servidor.shutdown()
