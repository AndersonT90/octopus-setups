#Requires -Version 5.1

function Invoke-AtualizacaoMother {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $repositorio = 'AndersonT90/octopus-setups'
    $servico = 'OFlow.Mother'
    $destino = 'C:\Octopus'
    $executavelDestino = Join-Path $destino 'OFlow.Mother.exe'

    function Passo($texto) { Write-Host ''; Write-Host "== $texto" -ForegroundColor Cyan }

    $identidade = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identidade.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ''
        Write-Host 'ERRO: abra o PowerShell como Administrador e rode novamente.' -ForegroundColor Red
        return
    }

    try {
        Passo 'Versao publicada'
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repositorio/releases/latest" -Headers @{ 'User-Agent' = 'OFlow-Setup' }
        $pacote = $release.assets | Where-Object { $_.name -like '*-windows.zip' } | Select-Object -First 1
        if (-not $pacote) { throw "A release $($release.tag_name) nao publica pacote windows." }
        if ($pacote.name -notmatch 'v(?<versao>\d+\.\d+\.\d+)-windows\.zip$') { throw "Nome de pacote fora do padrao: $($pacote.name)" }
        $versao = $Matches.versao
        Write-Host "  $($release.tag_name): $($pacote.name)"

        Passo 'Estado atual'
        $anterior = if (Test-Path -LiteralPath $executavelDestino) { (Get-Item -LiteralPath $executavelDestino).VersionInfo.FileVersion } else { 'nao instalado' }
        Write-Host "  Versao instalada: $anterior"
        Write-Host "  Versao publicada: $versao"
        if ($anterior -like "$versao*") {
            Write-Host ''
            Write-Host 'JA ESTA NA VERSAO PUBLICADA. Nada a fazer.' -ForegroundColor Green
            return
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
        Get-ChildItem -LiteralPath $extraido -Recurse | Unblock-File
        $instalador = Join-Path $extraido 'instalar-windows.ps1'
        if (-not (Test-Path -LiteralPath $instalador)) { throw 'instalar-windows.ps1 ausente no pacote.' }
        $configuracaoCliente = Join-Path $destino 'appsettings.json'
        if (Test-Path -LiteralPath $configuracaoCliente) {
            Copy-Item -LiteralPath $configuracaoCliente -Destination (Join-Path $extraido 'appsettings.json') -Force
            Write-Host '  Configuracao do cliente preservada'
        } else {
            Write-Host '  AVISO: instalacao nova; preencha RabbitMQ e Gates em C:\Octopus\appsettings.json depois' -ForegroundColor Yellow
        }

        Passo 'Instalacao'
        Push-Location $extraido
        try { & $instalador } finally { Pop-Location }

        Passo 'Verificacao'
        if (-not (Test-Path -LiteralPath $executavelDestino)) { throw 'O executavel nao chegou ao destino.' }
        $atual = (Get-Item -LiteralPath $executavelDestino).VersionInfo.FileVersion
        Write-Host "  Versao instalada agora: $atual"
        if ($atual -notlike "$versao*") { throw "O executavel continua em $atual; a atualizacao nao foi aplicada." }
        $estado = (Get-Service -Name $servico).Status
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
}

Invoke-AtualizacaoMother
