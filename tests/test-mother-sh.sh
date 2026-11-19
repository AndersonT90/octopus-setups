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
    trabalho_execucao=$1; base_execucao=$2; shift 2
    env -u CHAVE -u IV -u RABBITMQ -u SERIAL_MOTHER "$@" OFLOW_MODO_TESTE=1 OFLOW_API_BASE="$base_execucao" OFLOW_REPOSITORIO="teste/fixture" \
        OFLOW_DESTINO="$trabalho_execucao/destino" OFLOW_AMBIENTE="$trabalho_execucao/mother.env" \
        bash "$RAIZ/mother.sh" 2>&1 || true
}

CHAVE_TESTE=$(printf 'a%.0s' $(seq 1 64))
IV_TESTE=$(printf 'b%.0s' $(seq 1 32))
RABBITMQ_TESTE='amqp://cliente:senha-sintetica@fila.local.test:5672/'
SERIAL_TESTE=MOTHER-TESTE-1
PARAMETROS_NOVOS=(CHAVE="$CHAVE_TESTE" IV="$IV_TESTE" RABBITMQ="$RABBITMQ_TESTE" SERIAL_MOTHER="$SERIAL_TESTE")

configuracao() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["ConnectionStrings"]["RabbitMQ"], d["Parametros"]["Gates"])' "$1/destino/appsettings.json" 2>&1; }

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
saida=$(executar "$trabalho" "$base" "${PARAMETROS_NOVOS[@]}"); derrubar_fixture "$trabalho"
verificar 'anuncia a versao publicada' 'v9.9.9' "$saida"
verificar 'confere a integridade' 'SHA-256 confere' "$saida"
verificar 'conclui a atualizacao' 'MOTHER ATUALIZADO PARA 9.9.9' "$saida"
recusar 'nao deixa rastro de erro' 'ERRO:' "$saida"
verificar 'instalacao nova grava o RabbitMQ informado e mantem o Gates do pacote' "$RABBITMQ_TESTE https://api.octopustech.app" "$(configuracao "$trabalho")"
recusar 'nao exibe a senha do RabbitMQ' 'senha-sintetica' "$saida"
recusar 'nao exibe a CHAVE' "$CHAVE_TESTE" "$saida"
verificar 'instalacao nova registra o SERIAL_MOTHER no ambiente do servico' "SERIAL_MOTHER=$SERIAL_TESTE" "$(cat "$trabalho/mother.env" 2>&1)"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
saida=$(executar "$trabalho" "$base" CHAVE="$CHAVE_TESTE" IV="$IV_TESTE" RABBITMQ="$RABBITMQ_TESTE"); derrubar_fixture "$trabalho"
verificar 'instalacao nova sem SERIAL_MOTHER pede o parametro' 'informe SERIAL_MOTHER' "$saida"
recusar 'instalacao nova sem SERIAL_MOTHER nao baixa o pacote' '== Download' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
saida=$(executar "$trabalho" "$base" CHAVE="$CHAVE_TESTE" IV="$IV_TESTE" RABBITMQ="$RABBITMQ_TESTE" SERIAL_MOTHER='MOTHER 1'); derrubar_fixture "$trabalho"
verificar 'SERIAL_MOTHER com espaco e recusado' 'SERIAL_MOTHER nao pode ter espaco' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
saida=$(executar "$trabalho" "$base" CHAVE="$CHAVE_TESTE" IV="$IV_TESTE" SERIAL_MOTHER="$SERIAL_TESTE"); derrubar_fixture "$trabalho"
verificar 'instalacao nova sem RabbitMQ pede o parametro' 'informe RABBITMQ' "$saida"
recusar 'instalacao nova sem RabbitMQ nao baixa o pacote' '== Download' "$saida"
recusar 'instalacao nova sem RabbitMQ nao conclui' 'MOTHER ATUALIZADO' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
saida=$(executar "$trabalho" "$base" RABBITMQ="$RABBITMQ_TESTE" SERIAL_MOTHER="$SERIAL_TESTE"); derrubar_fixture "$trabalho"
verificar 'instalacao nova sem CHAVE e IV pede os parametros' 'informe CHAVE' "$saida"
recusar 'instalacao nova sem CHAVE e IV nao baixa o pacote' '== Download' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
saida=$(executar "$trabalho" "$base" CHAVE=123 IV="$IV_TESTE" RABBITMQ="$RABBITMQ_TESTE" SERIAL_MOTHER="$SERIAL_TESTE"); derrubar_fixture "$trabalho"
verificar 'CHAVE fora do formato e recusada' 'CHAVE deve ter 64' "$saida"
recusar 'CHAVE fora do formato nao conclui' 'MOTHER ATUALIZADO' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
mkdir -p "$trabalho/destino"; printf '9.9.8\n' > "$trabalho/destino/VERSAO"
printf '{"ConnectionStrings":{"RabbitMQ":"amqp://antigo@fila.local.test/"},"Parametros":{"Gates":"https://gates.local.test"}}' > "$trabalho/destino/appsettings.json"
printf 'CHAVE=%s\nIV=%s\n' "$CHAVE_TESTE" "$IV_TESTE" > "$trabalho/mother.env"
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'atualizacao sem parametros conclui' 'MOTHER ATUALIZADO PARA 9.9.9' "$saida"
verificar 'atualizacao preserva a configuracao do cliente' 'amqp://antigo@fila.local.test/ https://gates.local.test' "$(configuracao "$trabalho")"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
mkdir -p "$trabalho/destino"; printf '9.9.8\n' > "$trabalho/destino/VERSAO"
printf '{"ConnectionStrings":{"RabbitMQ":"amqp://antigo@fila.local.test/"},"Parametros":{"Gates":"https://gates.local.test"}}' > "$trabalho/destino/appsettings.json"
printf 'CHAVE=%s\nIV=%s\n' "$CHAVE_TESTE" "$IV_TESTE" > "$trabalho/mother.env"
saida=$(executar "$trabalho" "$base" RABBITMQ="$RABBITMQ_TESTE"); derrubar_fixture "$trabalho"
verificar 'atualizacao com RABBITMQ troca so a fila' "$RABBITMQ_TESTE https://gates.local.test" "$(configuracao "$trabalho")"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
mkdir -p "$trabalho/destino"; printf '9.9.8\n' > "$trabalho/destino/VERSAO"
printf '{"ConnectionStrings":{"RabbitMQ":"amqp://antigo@fila.local.test/"},"Parametros":{"Gates":"https://gates.local.test"}}' > "$trabalho/destino/appsettings.json"
printf 'CHAVE=%s\nIV=%s\nSERIAL_MOTHER=ANTIGO\nOUTRA=valor\n' "$CHAVE_TESTE" "$IV_TESTE" > "$trabalho/mother.env"
saida=$(executar "$trabalho" "$base" SERIAL_MOTHER="$SERIAL_TESTE"); derrubar_fixture "$trabalho"
ambiente=$(cat "$trabalho/mother.env")
verificar 'atualizacao com SERIAL_MOTHER troca o serial' "SERIAL_MOTHER=$SERIAL_TESTE" "$ambiente"
recusar 'atualizacao com SERIAL_MOTHER remove o serial antigo' 'SERIAL_MOTHER=ANTIGO' "$ambiente"
verificar 'atualizacao com SERIAL_MOTHER preserva as outras variaveis' 'OUTRA=valor' "$ambiente"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9)
mkdir -p "$trabalho/destino"; printf '9.9.9\n' > "$trabalho/destino/VERSAO"
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'reconhece que ja esta na versao publicada' 'JA ESTA NA VERSAO PUBLICADA' "$saida"
recusar 'nao reinstala' 'MOTHER ATUALIZADO' "$saida"

trabalho=$(mktemp -d); base=$(subir_fixture "$trabalho" 9.9.9 corromper)
saida=$(executar "$trabalho" "$base" "${PARAMETROS_NOVOS[@]}"); derrubar_fixture "$trabalho"
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
