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
MOTHER ATUALIZADO PARA 3.15.33
Licenca validada: Servidor autorizado
```

## On-premise (stack completa)

Somente **Ubuntu ou Debian**. Instala quando nao ha OFlow na maquina e atualiza
quando ha, decidindo pelo estado real dos containers:

```bash
curl -fsSL https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/onpremise.sh | sudo bash
```

Argumentos extras chegam ao script de operacao. Por exemplo, so o plano:

```bash
curl -fsSL https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/onpremise.sh | sudo bash -s -- --dry-run
```

Pre-requisitos: `curl`, `jq` e Docker acessivel ao root.

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
