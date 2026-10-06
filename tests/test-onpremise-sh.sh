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
    trabalho=$1; modo=${2:-}
    python3 "$RAIZ/tests/fixture-release.py" 9.9.9 "$trabalho/release" $modo > "$trabalho/base" 2>/dev/null &
    echo $! > "$trabalho/pid"
    for _ in $(seq 1 50); do [ -s "$trabalho/base" ] && break; sleep 0.1; done
    cat "$trabalho/base"
}
derrubar_fixture() { kill "$(cat "$1/pid")" 2>/dev/null || true; }

preparar() {
    trabalho=$1; kernel=$2; nomes=$3; rotulados=$4
    mkdir -p "$trabalho/bin"
    printf '%s\n' "$kernel" > "$trabalho/kernel"
    printf 'ID=ubuntu\nPRETTY_NAME="Ubuntu 24.04 LTS"\n' > "$trabalho/os-release"
    printf '%s' "$nomes" > "$trabalho/nomes"
    printf '%s' "$rotulados" > "$trabalho/rotulados"
    cat > "$trabalho/bin/docker" <<DOCKER
#!/usr/bin/env bash
case "\$1" in
    info) exit 0 ;;
    version) echo "27.0.0 amd64" ;;
    ps) case "\$*" in *label=com.octopus.oflow.role=father*--format\ rotulo-father*) [ -s "$trabalho/rotulados" ] && echo rotulo-father ;; *label=*) cat "$trabalho/rotulados" ;; *) cat "$trabalho/nomes" ;; esac ;;
    inspect) echo "octopusdevops/oflow_father:3.15.27" ;;
esac
exit 0
DOCKER
    chmod +x "$trabalho/bin/docker"
}

executar() {
    PATH="$1/bin:$PATH" OFLOW_MODO_TESTE=1 OFLOW_API_BASE="$2" OFLOW_REPOSITORIO="teste/fixture" \
        OFLOW_VERSAO_KERNEL="$1/kernel" OFLOW_OS_RELEASE="$1/os-release" \
        bash "$RAIZ/onpremise.sh" "${@:3}" 2>&1 || true
}

WSL='Linux version 5.15.167.4-microsoft-standard-WSL2 (root@1) #1 SMP'
LINUX='Linux version 6.8.0-45-generic (buildd@lcy02-amd64-075) #45-Ubuntu SMP'

trabalho=$(mktemp -d); preparar "$trabalho" "$WSL" $'oflow_father\npostgres\n' ''; base=$(subir_fixture "$trabalho")
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'detecta WSL' 'Plataforma wsl' "$saida"
verificar 'atualiza em WSL com --plataforma wsl' 'EXECUTADO atualizar-producao.sh ARGUMENTOS:--plataforma wsl' "$saida"
recusar 'nao forca linux no WSL' '--plataforma linux' "$saida"
recusar 'nao deixa rastro de erro no WSL' 'ERRO:' "$saida"

trabalho=$(mktemp -d); preparar "$trabalho" "$LINUX" $'oflow_father\n' ''; base=$(subir_fixture "$trabalho")
saida=$(executar "$trabalho" "$base" --dry-run); derrubar_fixture "$trabalho"
verificar 'detecta Linux nativo' 'Plataforma linux' "$saida"
verificar 'atualiza em Linux com --plataforma linux e repassa argumentos' 'EXECUTADO atualizar-producao.sh ARGUMENTOS:--plataforma linux --dry-run' "$saida"

trabalho=$(mktemp -d); preparar "$trabalho" "$LINUX" $'oflow-20260824T202338Z-svdcsublbcobca1-father\n' ''; base=$(subir_fixture "$trabalho")
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'reconhece geracao com hostname no nome' 'Operacao: ATUALIZAR' "$saida"

trabalho=$(mktemp -d); preparar "$trabalho" "$LINUX" $'oflow-geracao-x-pai\n' 'octopusdevops/oflow_father:3.15.40'; base=$(subir_fixture "$trabalho")
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'reconhece father pelo rotulo' 'Operacao: ATUALIZAR' "$saida"

trabalho=$(mktemp -d); preparar "$trabalho" "$WSL" $'postgres\n' ''; base=$(subir_fixture "$trabalho")
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'instala quando nao ha father' 'Operacao: INSTALAR' "$saida"
verificar 'instalador roda sem --plataforma, que ele nao aceita' 'EXECUTADO instalar-producao.sh ARGUMENTOS:' "$saida"
recusar 'instalador nao recebe --plataforma' 'instalar-producao.sh ARGUMENTOS:--plataforma' "$saida"

trabalho=$(mktemp -d); preparar "$trabalho" "$WSL" $'oflow_father\n' ''; base=$(subir_fixture "$trabalho" corromper)
saida=$(executar "$trabalho" "$base"); derrubar_fixture "$trabalho"
verificar 'recusa script com soma divergente' 'SHA-256 divergente' "$saida"
recusar 'nao executa script corrompido' 'EXECUTADO' "$saida"

TESTES=$((TESTES + 1))
grep -q '< /dev/tty' "$RAIZ/onpremise.sh" || falhar "onpremise.sh deve ler a confirmacao do terminal, pois em curl | bash o stdin e o proprio script"

if [ "$FALHAS" -ne 0 ]; then
    printf 'Tests: %s, Failed: %s\n' "$TESTES" "$FALHAS"
    exit 1
fi
printf 'Tests: %s, Failed: 0\n' "$TESTES"
