#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORIO=${OFLOW_REPOSITORIO:-AndersonT90/octopus-setups}
API=${OFLOW_API_BASE:-https://api.github.com}
VERSAO_KERNEL=${OFLOW_VERSAO_KERNEL:-/proc/version}
MODO_TESTE=${OFLOW_MODO_TESTE:-0}

passo() { printf '\n== %s\n' "$1"; }
erro() { printf '\nERRO: %s\n' "$1" >&2; printf 'Nada foi deixado pela metade. Envie esta saida para o time de desenvolvimento.\n' >&2; exit 1; }

[ "$MODO_TESTE" = 1 ] || [ "$(id -u)" -eq 0 ] || erro "Execute com sudo."
. "${OFLOW_OS_RELEASE:-/etc/os-release}" 2>/dev/null || erro "Distribuicao nao identificada; suportado somente Ubuntu ou Debian."
case "${ID:-}${ID_LIKE:-}" in *ubuntu*|*debian*) ;; *) erro "Suportado somente Ubuntu ou Debian; encontrado ${PRETTY_NAME:-desconhecido}." ;; esac
for programa in curl jq docker; do
    command -v "$programa" >/dev/null 2>&1 || erro "Instale $programa antes de continuar."
done
docker info >/dev/null 2>&1 || erro "O Docker nao esta acessivel para o root."

if grep -qi microsoft "$VERSAO_KERNEL" 2>/dev/null; then plataforma=wsl; else plataforma=linux; fi

passo 'Ambiente'
printf '  %s\n  Plataforma %s\n  Docker %s\n' "${PRETTY_NAME:-desconhecido}" "$plataforma" "$(docker version --format '{{.Server.Version}} {{.Server.Arch}}')"

passo 'Estado da instalacao'
existente=$({ docker ps -a --format '{{.Names}}'; docker ps -a --filter label=com.octopus.oflow.role=father --format 'rotulo-father'; } | grep -Ec '^(oflow_father|oflow-[0-9A-Za-z-]+-father|rotulo-father)$' || true)
if [ "$existente" -gt 0 ]; then
    operacao=atualizar
    versao_atual=$(docker ps --filter label=com.octopus.oflow.role=father --format '{{.Image}}' | head -1)
    [ -n "$versao_atual" ] || versao_atual=$(docker inspect oflow_father --format '{{.Config.Image}}' 2>/dev/null || echo desconhecida)
    printf '  Instalacao encontrada: %s\n  Operacao: ATUALIZAR\n' "$versao_atual"
else
    operacao=instalar
    printf '  Nenhuma instalacao encontrada\n  Operacao: INSTALAR\n'
fi

passo 'Script publicado'
release=$(curl -fsSL "$API/repos/$REPOSITORIO/releases/latest") || erro "Nao foi possivel consultar a release publicada."
tag=$(printf '%s' "$release" | jq -r '.tag_name')
if [ "$operacao" = atualizar ]; then nome=atualizar-producao.sh; else nome=instalar-producao.sh; fi
url=$(printf '%s' "$release" | jq -r --arg nome "$nome" '.assets[] | select(.name == $nome) | .browser_download_url')
[ -n "$url" ] && [ "$url" != null ] || erro "A release $tag nao publica $nome."
trabalho=$(mktemp -d /tmp/oflow-onpremise-XXXXXX)
trap 'rm -rf "$trabalho"' EXIT
curl -fsSL "$url" -o "$trabalho/$nome"
printf '  %s: %s\n' "$tag" "$nome"

passo 'Integridade'
url_somas=$(printf '%s' "$release" | jq -r '.assets[] | select(.name | contains("SHA256SUMS")) | .browser_download_url' | head -1)
[ -n "$url_somas" ] && [ "$url_somas" != null ] || erro "A release nao publica SHA256SUMS; execucao recusada."
curl -fsSL "$url_somas" -o "$trabalho/SHA256SUMS.txt"
esperado=$(grep -F "$nome" "$trabalho/SHA256SUMS.txt" | awk '{print $1}' | head -1)
[ -n "$esperado" ] || erro "SHA256SUMS nao lista $nome."
obtido=$(sha256sum "$trabalho/$nome" | awk '{print $1}')
[ "$esperado" = "$obtido" ] || erro "SHA-256 divergente; o download veio corrompido."
printf '  SHA-256 confere\n'

passo 'Execucao'
chmod +x "$trabalho/$nome"
printf '  A partir daqui quem conduz e o %s.\n' "$nome"
if [ "$operacao" = atualizar ]; then
    "$trabalho/$nome" --plataforma "$plataforma" "$@"
else
    "$trabalho/$nome" "$@"
fi
