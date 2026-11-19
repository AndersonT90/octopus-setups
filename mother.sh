#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORIO=${OFLOW_REPOSITORIO:-AndersonT90/octopus-setups}
API=${OFLOW_API_BASE:-https://api.github.com}
DESTINO=${OFLOW_DESTINO:-/opt/oflow-mother}
SERVICO=${OFLOW_SERVICO:-oflow-mother}
AMBIENTE=${OFLOW_AMBIENTE:-/etc/oflow/mother.env}
CHAVE=${CHAVE:-}
IV=${IV:-}
RABBITMQ=${RABBITMQ:-}
SERIAL_MOTHER=${SERIAL_MOTHER:-}
PADRAO_SERIAL='^[^[:space:]"'"'"'=]+$'
COMANDO_INSTALACAO_NOVA="curl -fsSL https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/mother.sh | sudo CHAVE=<64 hex> IV=<32 hex> RABBITMQ='amqp://usuario:senha@servidor:5672/' SERIAL_MOTHER=<serial do Mother> bash"
MODO_TESTE=${OFLOW_MODO_TESTE:-0}

passo() { printf '\n== %s\n' "$1"; }
erro() { printf '\nERRO: %s\n' "$1" >&2; printf 'Nada foi deixado pela metade. Envie esta saida para o time de desenvolvimento.\n' >&2; exit 1; }

[ "$MODO_TESTE" = 1 ] || [ "$(id -u)" -eq 0 ] || erro "Execute com sudo."
for programa in curl unzip jq python3; do
    command -v "$programa" >/dev/null 2>&1 || erro "Instale $programa antes de continuar: apt-get install -y $programa"
done

passo 'Versao publicada'
release=$(curl -fsSL "$API/repos/$REPOSITORIO/releases/latest") || erro "Nao foi possivel consultar a release publicada."
tag=$(printf '%s' "$release" | jq -r '.tag_name')
url_pacote=$(printf '%s' "$release" | jq -r '.assets[] | select(.name | endswith("-linux.zip")) | .browser_download_url' | head -1)
nome_pacote=${url_pacote##*/}
[ -n "$url_pacote" ] && [ "$url_pacote" != null ] || erro "A release $tag nao publica pacote linux."
versao=${nome_pacote#*v}
versao=${versao%-linux.zip}
case "$versao" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) erro "Nome de pacote fora do padrao: $nome_pacote" ;;
esac
printf '  %s: %s\n' "$tag" "$nome_pacote"

passo 'Estado atual'
anterior=nao_instalado
[ -f "$DESTINO/VERSAO" ] && anterior=$(cat "$DESTINO/VERSAO")
printf '  Versao instalada: %s\n  Versao publicada: %s\n' "$anterior" "$versao"
if [ "$anterior" = "$versao" ]; then
    printf '\nJA ESTA NA VERSAO PUBLICADA. Nada a fazer.\n'
    exit 0
fi

passo 'Parametros'
if [ -n "$CHAVE" ] || [ -n "$IV" ] || ! grep -q '^CHAVE=' "$AMBIENTE" 2>/dev/null; then
    [ -n "$CHAVE" ] && [ -n "$IV" ] || erro "Instalacao nova: informe CHAVE e IV da licenca do cliente. Exemplo: $COMANDO_INSTALACAO_NOVA"
    [[ "$CHAVE" =~ ^[[:xdigit:]]{64}$ ]] || erro "CHAVE deve ter 64 caracteres hexadecimais."
    [[ "$IV" =~ ^[[:xdigit:]]{32}$ ]] || erro "IV deve ter 32 caracteres hexadecimais."
    export CHAVE IV
    printf '  CHAVE e IV informados\n'
else
    printf '  CHAVE e IV ja registrados nesta maquina\n'
fi
if [ -n "$RABBITMQ" ]; then
    printf '  RabbitMQ informado\n'
elif [ -f "$DESTINO/appsettings.json" ]; then
    printf '  RabbitMQ da configuracao atual\n'
else
    erro "Instalacao nova: informe RABBITMQ com a conexao da fila do cliente. Exemplo: $COMANDO_INSTALACAO_NOVA"
fi
if [ -n "$SERIAL_MOTHER" ]; then
    [[ "$SERIAL_MOTHER" =~ $PADRAO_SERIAL ]] || erro "SERIAL_MOTHER nao pode ter espaco, aspas nem sinal de igual."
    printf '  SERIAL_MOTHER informado\n'
elif [ -f "$DESTINO/appsettings.json" ]; then
    printf '  SERIAL_MOTHER mantido\n'
else
    erro "Instalacao nova: informe SERIAL_MOTHER com o serial cadastrado na licenca do cliente. Exemplo: $COMANDO_INSTALACAO_NOVA"
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
fi
if [ -n "$RABBITMQ" ]; then
    jq --arg conexao "$RABBITMQ" '.ConnectionStrings.RabbitMQ = $conexao' "$trabalho/pacote/appsettings.json" > "$trabalho/appsettings.json" \
        || erro "Nao foi possivel gravar o RabbitMQ na configuracao."
    mv "$trabalho/appsettings.json" "$trabalho/pacote/appsettings.json"
    printf '  RabbitMQ gravado na configuracao\n'
fi

registrar_serial() {
    local proximo
    mkdir -p "$(dirname "$AMBIENTE")"
    chmod 700 "$(dirname "$AMBIENTE")"
    proximo=$(mktemp "$trabalho/ambiente-XXXXXX")
    [ -f "$AMBIENTE" ] && grep -v '^SERIAL_MOTHER=' "$AMBIENTE" > "$proximo" || true
    printf 'SERIAL_MOTHER=%s\n' "$SERIAL_MOTHER" >> "$proximo"
    chmod 600 "$proximo"
    mv "$proximo" "$AMBIENTE"
}
if [ -n "$SERIAL_MOTHER" ]; then
    registrar_serial || erro "Nao foi possivel registrar o SERIAL_MOTHER em $AMBIENTE."
    printf '  SERIAL_MOTHER registrado no ambiente do servico\n'
fi

passo 'Instalacao'
if [ "$MODO_TESTE" = 1 ]; then
    mkdir -p "$DESTINO"
    cp "$trabalho/pacote/OFlow.Mother" "$DESTINO/OFlow.Mother"
    cp "$trabalho/pacote/appsettings.json" "$DESTINO/appsettings.json"
    printf '  MODO DE TESTE: instalador nao executado\n'
else
    (cd "$trabalho/pacote" && ./instalar-linux.sh) || erro "O instalador falhou."
fi

passo 'Verificacao'
if [ "$MODO_TESTE" != 1 ]; then
    systemctl is-active --quiet "$SERVICO" || erro "O servico $SERVICO nao ficou ativo."
    sleep 12
fi
printf '  Servico: ativo\n'
if [ "$MODO_TESTE" != 1 ] && journalctl -u "$SERVICO" -n 60 --no-pager 2>/dev/null | grep -q 'Servidor autorizado'; then
    printf '  Licenca validada: Servidor autorizado\n'
elif [ "$MODO_TESTE" != 1 ]; then
    printf '  AVISO: "Servidor autorizado" ainda nao apareceu no log. Ultimas linhas:\n'
    journalctl -u "$SERVICO" -n 12 --no-pager 2>/dev/null | sed 's/^/    /'
fi

printf '%s\n' "$versao" > "$DESTINO/VERSAO"
printf '\nMOTHER ATUALIZADO PARA %s\n' "$versao"
