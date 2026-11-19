#Requires -Version 5.1

function Invoke-AtualizacaoMother {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $repositorio = if ($env:OFLOW_REPOSITORIO) { $env:OFLOW_REPOSITORIO } else { 'AndersonT90/octopus-setups' }
    $api = if ($env:OFLOW_API_BASE) { $env:OFLOW_API_BASE } else { 'https://api.github.com' }
    $servico = 'OFlow.Mother'
    $destino = if ($env:OFLOW_DESTINO) { $env:OFLOW_DESTINO } else { 'C:\Octopus' }
    $executavelDestino = Join-Path $destino 'OFlow.Mother.exe'
    $configuracaoCliente = Join-Path $destino 'appsettings.json'
    function Obter-SerialRegistrado {
        if ($env:OFLOW_MODO_TESTE -eq '1') {
            if (Test-Path -LiteralPath $env:OFLOW_SERIAL_ARQUIVO) { return (Get-Content -LiteralPath $env:OFLOW_SERIAL_ARQUIVO -Raw).Trim() }
            return ''
        }
        return [Environment]::GetEnvironmentVariable('SERIAL_MOTHER', 'Machine')
    }
    function Registrar-Serial($serial) {
        if ($env:OFLOW_MODO_TESTE -eq '1') { Set-Content -LiteralPath $env:OFLOW_SERIAL_ARQUIVO -Value $serial -NoNewline; return }
        [Environment]::SetEnvironmentVariable('SERIAL_MOTHER', $serial, 'Machine')
    }
    $comandoInstalacaoNova = "`$env:CHAVE='<64 hex>'; `$env:IV='<32 hex>'; `$env:RABBITMQ='amqp://usuario:senha@servidor:5672/'; `$env:SERIAL_MOTHER='<serial do Mother>'; irm https://raw.githubusercontent.com/AndersonT90/octopus-setups/main/mother.ps1 | iex"

    function Passo($texto) { Write-Host ''; Write-Host "== $texto" -ForegroundColor Cyan }

    if ($env:OFLOW_MODO_TESTE -ne '1') {
        $identidade = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identidade.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host ''
            Write-Host 'ERRO: abra o PowerShell como Administrador e rode novamente.' -ForegroundColor Red
            return
        }
    }

    Write-Host ''
    Write-Host 'OFlow Mother - instalacao e atualizacao (script rev 3)' -ForegroundColor Cyan

    try {
        Passo 'Versao publicada'
        $release = Invoke-RestMethod -Uri "$api/repos/$repositorio/releases/latest" -Headers @{ 'User-Agent' = 'OFlow-Setup' }
        $pacote = $release.assets | Where-Object { $_.name -like '*-windows.zip' } | Select-Object -First 1
        if (-not $pacote) { throw "A release $($release.tag_name) nao publica pacote windows." }
        if ($pacote.name -notmatch 'v(?<versao>\d+\.\d+\.\d+)-windows\.zip$') { throw "Nome de pacote fora do padrao: $($pacote.name)" }
        $versao = $Matches.versao
        Write-Host "  $($release.tag_name): $($pacote.name)"

        Passo 'Estado atual'
        $anterior = if (-not (Test-Path -LiteralPath $executavelDestino)) { 'nao instalado' }
            elseif ($env:OFLOW_MODO_TESTE -eq '1') { (Get-Content -LiteralPath $executavelDestino -Raw).Trim() }
            else { (Get-Item -LiteralPath $executavelDestino).VersionInfo.FileVersion }
        Write-Host "  Versao instalada: $anterior"
        Write-Host "  Versao publicada: $versao"
        if ($anterior -like "$versao*") {
            Write-Host ''
            Write-Host 'JA ESTA NA VERSAO PUBLICADA. Nada a fazer.' -ForegroundColor Green
            return
        }

        Passo 'Parametros'
        if ($env:CHAVE -or $env:IV -or -not (Test-Path -LiteralPath $executavelDestino)) {
            if (-not $env:CHAVE -or -not $env:IV) { throw "Instalacao nova: informe CHAVE e IV da licenca do cliente. Exemplo: $comandoInstalacaoNova" }
            if ($env:CHAVE -notmatch '^[A-Fa-f0-9]{64}$') { throw 'CHAVE deve ter 64 caracteres hexadecimais.' }
            if ($env:IV -notmatch '^[A-Fa-f0-9]{32}$') { throw 'IV deve ter 32 caracteres hexadecimais.' }
            Write-Host '  CHAVE e IV informados'
        } else {
            Write-Host '  CHAVE e IV ja registrados no servico'
        }
        if ($env:RABBITMQ) {
            Write-Host '  RabbitMQ informado'
        } elseif (Test-Path -LiteralPath $configuracaoCliente) {
            Write-Host '  RabbitMQ da configuracao atual'
        } else {
            throw "Instalacao nova: informe RABBITMQ com a conexao da fila do cliente. Exemplo: $comandoInstalacaoNova"
        }
        if ($env:SERIAL_MOTHER) {
            if ($env:SERIAL_MOTHER -notmatch '^[^\s"''=]+$') { throw 'SERIAL_MOTHER nao pode ter espaco, aspas nem sinal de igual.' }
            Write-Host '  SERIAL_MOTHER informado'
        } elseif ((Obter-SerialRegistrado) -or (Test-Path -LiteralPath $executavelDestino)) {
            Write-Host '  SERIAL_MOTHER mantido'
        } else {
            throw "Instalacao nova: informe SERIAL_MOTHER com o serial cadastrado na licenca do cliente. Exemplo: $comandoInstalacaoNova"
        }

        Passo 'Download'
        $trabalho = Join-Path $env:TEMP "oflow-mother-$versao"
        if (Test-Path -LiteralPath $trabalho) { Remove-Item -LiteralPath $trabalho -Recurse -Force }
        New-Item -ItemType Directory -Path $trabalho | Out-Null
        $arquivo = Join-Path $trabalho $pacote.name
        Invoke-WebRequest -Uri $pacote.browser_download_url -OutFile $arquivo -UseBasicParsing
        Write-Host "  $([Math]::Round((Get-Item $arquivo).Length / 1MB)) MB"

        Passo 'Integridade'
        $somas = $release.assets | Where-Object { $_.name -like '*SHA256SUMS*' } | Select-Object -First 1
        if (-not $somas) { throw 'A release nao publica SHA256SUMS; instalacao recusada.' }
        $listagem = Join-Path $trabalho 'SHA256SUMS.txt'
        Invoke-WebRequest -Uri $somas.browser_download_url -OutFile $listagem -UseBasicParsing
        $linha = Select-String -LiteralPath $listagem -Pattern ([regex]::Escape($pacote.name)) | Select-Object -First 1
        if (-not $linha) { throw "SHA256SUMS nao lista $($pacote.name)." }
        $esperado = $linha.Line.Split(' ')[0].ToLower()
        $obtido = (Get-FileHash -LiteralPath $arquivo -Algorithm SHA256).Hash.ToLower()
        if ($esperado -ne $obtido) { throw 'SHA-256 divergente; o download veio corrompido.' }
        Write-Host '  SHA-256 confere'

        Passo 'Preparacao'
        $extraido = Join-Path $trabalho 'pacote'
        Expand-Archive -LiteralPath $arquivo -DestinationPath $extraido -Force
        if ($IsWindows -ne $false) { Get-ChildItem -LiteralPath $extraido -Recurse | Unblock-File }
        $instalador = Join-Path $extraido 'instalar-windows.ps1'
        if (-not (Test-Path -LiteralPath $instalador)) { throw 'instalar-windows.ps1 ausente no pacote.' }
        $configuracaoPacote = Join-Path $extraido 'appsettings.json'
        if (Test-Path -LiteralPath $configuracaoCliente) {
            Copy-Item -LiteralPath $configuracaoCliente -Destination $configuracaoPacote -Force
            Write-Host '  Configuracao do cliente preservada'
        }
        if ($env:RABBITMQ) {
            $configuracao = Get-Content -LiteralPath $configuracaoPacote -Raw | ConvertFrom-Json
            if (-not $configuracao.ConnectionStrings) { $configuracao | Add-Member -NotePropertyName ConnectionStrings -NotePropertyValue ([pscustomobject]@{}) }
            $configuracao.ConnectionStrings | Add-Member -NotePropertyName RabbitMQ -NotePropertyValue $env:RABBITMQ -Force
            $configuracao | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configuracaoPacote -Encoding UTF8
            Write-Host '  RabbitMQ gravado na configuracao'
        }

        if ($env:SERIAL_MOTHER) {
            Registrar-Serial $env:SERIAL_MOTHER
            Write-Host '  SERIAL_MOTHER registrado na maquina'
        }

        Passo 'Instalacao'
        if ($env:OFLOW_MODO_TESTE -eq '1') {
            Write-Host '  MODO DE TESTE: instalador nao executado'
            Copy-Item -LiteralPath (Join-Path $extraido 'OFlow.Mother.exe') -Destination $executavelDestino -Force
            Copy-Item -LiteralPath $configuracaoPacote -Destination $configuracaoCliente -Force
        } else {
            Push-Location $extraido
            try { & $instalador } finally { Pop-Location }
        }

        Passo 'Verificacao'
        if (-not (Test-Path -LiteralPath $executavelDestino)) { throw 'O executavel nao chegou ao destino.' }
        $atual = if ($env:OFLOW_MODO_TESTE -eq '1') { $versao } else { (Get-Item -LiteralPath $executavelDestino).VersionInfo.FileVersion }
        Write-Host "  Versao instalada agora: $atual"
        if ($atual -notlike "$versao*") { throw "O executavel continua em $atual; a atualizacao nao foi aplicada." }
        $estado = if ($env:OFLOW_MODO_TESTE -eq '1') { 'Running' } else { (Get-Service -Name $servico).Status }
        Write-Host "  Servico: $estado"
        if ($estado -ne 'Running') { throw 'O servico nao ficou em execucao.' }

        Start-Sleep -Seconds 12
        $log = Get-ChildItem -LiteralPath (Join-Path $destino 'logs') -Filter '*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($log) {
            $linhas = Get-Content -LiteralPath $log.FullName -Tail 40
            if ($linhas -match 'Servidor autorizado') {
                Write-Host '  Licenca validada: Servidor autorizado' -ForegroundColor Green
            } else {
                Write-Host '  AVISO: "Servidor autorizado" ainda nao apareceu no log. Ultimas linhas:' -ForegroundColor Yellow
                $linhas | Select-Object -Last 12 | ForEach-Object { Write-Host "    $_" }
            }
        }

        Write-Host ''
        Write-Host "MOTHER ATUALIZADO PARA $atual" -ForegroundColor Green
    }
    catch {
        Write-Host ''
        Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Nada foi deixado pela metade. Envie esta tela para o time de desenvolvimento.'
    }
    finally {
        Remove-Item -Path Env:CHAVE, Env:IV, Env:RABBITMQ, Env:SERIAL_MOTHER -ErrorAction SilentlyContinue
    }
}

Invoke-AtualizacaoMother
