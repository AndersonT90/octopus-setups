# Octopus Setups

Instaladores do OFlow para servidores de cliente. Um arquivo, dois cliques.

## Atualizar ou instalar o Mother (Windows)

1. Baixe **[OFlow.cmd](https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/windows/OFlow.cmd)** no servidor do cliente.
2. Clique duas vezes e aceite o pedido de Administrador.

Ele busca a versao publicada mais recente, confere o SHA-256, extrai e instala.
Nada precisa ser digitado. Ao final aparece:

```
MOTHER ATUALIZADO PARA 3.15.33.0
Licenca validada: Servidor autorizado
```

Se o servidor ja estiver na versao publicada, ele informa e sai sem alterar nada.
Qualquer falha para a execucao com uma linha `ERRO:` explicando o motivo.

## O que e preservado no servidor

Configuracao do cliente (`appsettings.json`), licenca, `CHAVE`, `IV`, `SERIAL_MOTHER`
e o banco do Mother. Os pacotes publicados aqui saem com placeholders: nenhum segredo
de cliente entra em release.

## Releases

Cada release traz o pacote `Mother.<versao>.zip` e o `SHA256SUMS.txt` correspondente.
Os binarios sao gerados a partir de tag anotada do repositorio do produto, com
proveniencia registrada em `provenance.json`.
