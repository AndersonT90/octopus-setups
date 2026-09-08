#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TESTES=0
FALHAS=0

falhar() { printf 'ASSERT FAILED: %s\n' "$*" >&2; FALHAS=$((FALHAS + 1)); }
verificar() {
    TESTES=$((TESTES + 1))
    case "$3" in *"$2"*) ;; *) falhar "$1
    esperado conter: $2
    obtido: $3" ;; esac
}
recusar() {
    TESTES=$((TESTES + 1))
    case "$3" in *"$2"*) falhar "$1
    nao deveria conter: $2" ;; *) ;; esac
}

subir_fixture() {
    trabalho=$1; versao=$2; modo=${3:-}
    python3 "$RAIZ/tests/fixture-release.py" "$versao" "$trabalho/release" $modo > "$trabalho/base" 2>/dev/null &
    echo $! > "$trabalho/pid"
    for _ in $(seq 1 50); do [ -s "$trabalho/base" ] && break; sleep 0.1; done
    cat "$trabalho/base"
}
derrubar_fixture() { kill "$(cat "$1/pid")" 2>/dev/null || true; }

executar() {
    OFLOW_MODO_TESTE=1 OFLOW_API_BASE="$2" OFLOW_REPOSITORIO="teste/fixture" OFLOW_DESTINO="$1/destino" \
        bash "$RAIZ/mother.sh" 2>&1 || true
}

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'anuncia a versao publicada' 'v9.9.9' "$saida"
verificar 'confere a integridade' 'SHA-256 confere' "$saida"
verificar 'conclui a atualizacao' 'MOTHER ATUALIZADO PARA 9.9.9' "$saida"
recusar 'nao deixa rastro de erro' 'ERRO:' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
mkdir -p "$trabalho/destino"; printf '9.9.9\n' > "$trabalho/destino/VERSAO"
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'reconhece que ja esta na versao publicada' 'JA ESTA NA VERSAO PUBLICADA' "$saida"
recusar 'nao reinstala' 'MOTHER ATUALIZADO' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9 corromper)
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'recusa pacote com soma divergente' 'SHA-256 divergente' "$saida"
recusar 'nao conclui com pacote corrompido' 'MOTHER ATUALIZADO' "$saida"

TESTES=$((TESTES + 1))
bash -n "$RAIZ/mother.sh" || falhar "mother.sh com erro de sintaxe"
TESTES=$((TESTES + 1))
bash -n "$RAIZ/onpremise.sh" || falhar "onpremise.sh com erro de sintaxe"

TESTES=$((TESTES + 1))
if ! grep -q 'SHA256SUMS' "$RAIZ/onpremise.sh"; then
    falhar "onpremise.sh deve conferir SHA256SUMS antes de executar"
fi

if [ "$FALHAS" -ne 0 ]; then
    printf 'Tests: %s, Failed: %s\n' "$TESTES" "$FALHAS"
    exit 1
fi
printf 'Tests: %s, Failed: 0\n' "$TESTES"
