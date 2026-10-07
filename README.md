# Octopus Setups

Canal de instalacao do OFlow em servidores de cliente. Um comando por caso.

## Mother

O Mother roda como servico no servidor do cliente e conversa com as integracoes.

**Windows Server** — PowerShell como Administrador:

```powershell
irm https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/mother.ps1 | iex
```

**Ubuntu ou Debian** — terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/mother.sh | sudo bash
```

O script busca a versao publicada, confere o SHA-256, para o servico, troca o
binario, religa e valida. Se o servidor ja estiver na versao publicada, ele diz
e sai sem alterar nada. Ao final:

```
MOTHER ATUALIZADO PARA 3.15.40
Licenca validada: Servidor autorizado
```

## On-premise (stack completa)

Somente **Ubuntu ou Debian**, nativo ou no WSL do Windows Server. Instala quando
nao ha OFlow na maquina e atualiza quando ha, decidindo pelo estado real dos
containers. A plataforma (WSL ou Linux nativo) e detectada pelo kernel e repassada
ao atualizador:

```bash
curl -fsSL https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/onpremise.sh | sudo bash
```

Argumentos extras chegam ao script de operacao. Por exemplo, so o plano:

```bash
curl -fsSL https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/onpremise.sh | sudo bash -s -- --dry-run
```

Pre-requisitos: `curl`, `jq` e Docker acessivel ao root.

## Versoes publicadas

| Release | Mother | Stack on-premise (atualizador) |
| --- | --- | --- |
| v3.15.40 | 3.15.40 | Father 3.15.41, API 3.15.29 e Web 3.15.3 |

O atualizador da stack fixa cada imagem pelo digest. Quando so o Father muda, o
`atualizar-producao.sh` e o `SHA256SUMS.txt` da release vigente sao republicados
e o Mother continua na versao da release.

## O que e preservado no servidor

Configuracao do cliente, licenca, `CHAVE`, `IV`, `SERIAL_MOTHER`, bancos e volumes.
Os pacotes publicados aqui saem com placeholders: nenhum segredo de cliente entra
em release.

## Integridade

Toda execucao confere o `SHA256SUMS.txt` da release antes de instalar, e recusa
seguir se a release nao publicar essa listagem. Os binarios sao gerados a partir
de tag anotada do repositorio do produto, com proveniencia em `provenance.json`.

## Falhas

Qualquer erro para a execucao com uma linha `ERRO:` dizendo o motivo. O
atualizador da stack imprime um ID de execucao para retomada (`--continuar <id>`)
e mantem a geracao anterior para rollback (`--rollback <id>`).

## Testes

`tests/` exercita os scripts contra uma release falsa servida localmente
(`tests/fixture-release.py`), sem tocar em cliente nenhum:

```bash
bash tests/test-mother-sh.sh    # mother.sh e onpremise.sh
bash tests/test-mother-ps1.sh   # mother.ps1, requer pwsh
```

Cobrem o caminho feliz, o caso "ja esta na versao publicada", a recusa quando o
`SHA256SUMS` diverge e — no PowerShell — a garantia de que o script **nao encerra a
sessao do operador**, que foi o defeito observado em producao em 2026-09-08.

O CI roda tudo em `ubuntu-latest`, inclusive o PowerShell, via `pwsh`, que ja vem
instalado no runner. Runner Windows custa o dobro de minutos e nao e necessario
para o que esses testes verificam.
