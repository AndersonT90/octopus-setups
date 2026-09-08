#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORIO=AndersonT90/octopus-setups
DESTINO=/opt/oflow-mother
SERVICO=oflow-mother

passo() { printf '\n== %s\n' "$1"; }
erro() { printf '\nERRO: %s\n' "$1" >&2; printf 'Nada foi deixado pela metade. Envie esta saida para o time de desenvolvimento.\n' >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || erro "Execute com sudo."
for programa in curl unzip jq python3; do
    command -v "$programa" >/dev/null 2>&1 || erro "Instale $programa antes de continuar: apt-get install -y $programa"
done

passo 'Versao publicada'
release=$(curl -fsSL "https://api.github.com/repos/$REPOSITORIO/releases/latest") || erro "Nao foi possivel consultar a release publicada."
tag=$(printf '%s' "$release" | jq -r '.tag_name')
url_pacote=$(printf '%s' "$release" | jq -r '.assets[] | select(.name | endswith("-linux.zip")) | .browser_download_url' | head -1)
nome_pacote=${url_pacote##*/}
[ -n "$url_pacote" ] && [ "$url_pacote" != null ] || erro "A release $tag nao publica pacote linux."
versao=$(printf '%s' "$nome_pacote" | sed -n 's/.*v\([0-9]\+\.[0-9]\+\.[0-9]\+\)-linux\.zip/\1/p')
[ -n "$versao" ] || erro "Nome de pacote fora do padrao: $nome_pacote"
printf '  %s: %s\n' "$tag" "$nome_pacote"

passo 'Estado atual'
anterior=nao_instalado
[ -f "$DESTINO/VERSAO" ] && anterior=$(cat "$DESTINO/VERSAO")
printf '  Versao instalada: %s\n  Versao publicada: %s\n' "$anterior" "$versao"
if [ "$anterior" = "$versao" ]; then
    printf '\nJA ESTA NA VERSAO PUBLICADA. Nada a fazer.\n'
    exit 0
fi

passo 'Download'
trabalho=$(mktemp -d /tmp/oflow-mother-XXXXXX)
trap 'rm -rf "$trabalho"' EXIT
curl -fsSL "$url_pacote" -o "$trabalho/$nome_pacote" || erro "Falha no download do pacote."
printf '  %s MB\n' "$(( $(stat -c %s "$trabalho/$nome_pacote") / 1048576 ))"

passo 'Integridade'
url_somas=$(printf '%s' "$release" | jq -r '.assets[] | select(.name | contains("SHA256SUMS")) | .browser_download_url' | head -1)
[ -n "$url_somas" ] && [ "$url_somas" != null ] || erro "A release nao publica SHA256SUMS; instalacao recusada."
curl -fsSL "$url_somas" -o "$trabalho/SHA256SUMS.txt"
esperado=$(grep -F "$nome_pacote" "$trabalho/SHA256SUMS.txt" | awk '{print $1}' | head -1)
[ -n "$esperado" ] || erro "SHA256SUMS nao lista $nome_pacote."
obtido=$(sha256sum "$trabalho/$nome_pacote" | awk '{print $1}')
[ "$esperado" = "$obtido" ] || erro "SHA-256 divergente; o download veio corrompido."
printf '  SHA-256 confere\n'

passo 'Preparacao'
unzip -q "$trabalho/$nome_pacote" -d "$trabalho/pacote"
instalador="$trabalho/pacote/instalar-linux.sh"
[ -f "$instalador" ] || erro "instalar-linux.sh ausente no pacote."
chmod +x "$instalador"
if [ -f "$DESTINO/appsettings.json" ]; then
    cp "$DESTINO/appsettings.json" "$trabalho/pacote/appsettings.json"
    printf '  Configuracao do cliente preservada\n'
else
    printf '  AVISO: instalacao nova; preencha RabbitMQ e Gates em %s/appsettings.json depois\n' "$DESTINO"
fi

passo 'Instalacao'
(cd "$trabalho/pacote" && ./instalar-linux.sh) || erro "O instalador falhou."

passo 'Verificacao'
systemctl is-active --quiet "$SERVICO" || erro "O servico $SERVICO nao ficou ativo."
printf '  Servico: ativo\n'
sleep 12
if journalctl -u "$SERVICO" -n 60 --no-pager 2>/dev/null | grep -q 'Servidor autorizado'; then
    printf '  Licenca validada: Servidor autorizado\n'
else
    printf '  AVISO: "Servidor autorizado" ainda nao apareceu no log. Ultimas linhas:\n'
    journalctl -u "$SERVICO" -n 12 --no-pager 2>/dev/null | sed 's/^/    /'
fi

printf '%s\n' "$versao" > "$DESTINO/VERSAO"
printf '\nMOTHER ATUALIZADO PARA %s\n' "$versao"
