@echo off
setlocal
net session >nul 2>&1
if errorlevel 1 (
  echo Solicitando permissao de Administrador...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$conteudo = Get-Content -Raw -LiteralPath '%~f0'; $inicio = $conteudo.IndexOf('#::POWERSHELL::'); Invoke-Expression $conteudo.Substring($inicio)"
echo.
echo Pressione qualquer tecla para fechar.
pause >nul
exit /b

#::POWERSHELL::
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repositorio = 'AndersonT90/octopus-setups'

function Passo($texto) { Write-Host ''; Write-Host "== $texto" -ForegroundColor Cyan }
function Erro($texto) { Write-Host ''; Write-Host "ERRO: $texto" -ForegroundColor Red; Write-Host 'Nada foi deixado pela metade. Envie esta tela para o time de desenvolvimento.'; exit 1 }

try {
    Passo 'Versao publicada'
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repositorio/releases/latest" -Headers @{ 'User-Agent' = 'OFlow-Setup' }
    $pacote = $release.assets | Where-Object { $_.name -like 'Mother.*.zip' } | Select-Object -First 1
    $somas = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
    if (-not $pacote) { Erro "A release $($release.tag_name) nao publica um pacote Mother.*.zip." }
    Write-Host "  $($release.tag_name): $($pacote.name)"

    Passo 'Download'
    $trabalho = Join-Path $env:TEMP "oflow-setup-$($release.tag_name)"
    if (Test-Path -LiteralPath $trabalho) { Remove-Item -LiteralPath $trabalho -Recurse -Force }
    New-Item -ItemType Directory -Path $trabalho | Out-Null
    $arquivo = Join-Path $trabalho $pacote.name
    Invoke-WebRequest -Uri $pacote.browser_download_url -OutFile $arquivo -UseBasicParsing
    Write-Host "  $([Math]::Round((Get-Item $arquivo).Length / 1MB)) MB baixados"

    Passo 'Integridade'
    if ($somas) {
        $listagem = Join-Path $trabalho 'SHA256SUMS.txt'
        Invoke-WebRequest -Uri $somas.browser_download_url -OutFile $listagem -UseBasicParsing
        $linha = Select-String -LiteralPath $listagem -Pattern ([regex]::Escape($pacote.name)) | Select-Object -First 1
        if (-not $linha) { Erro "SHA256SUMS.txt nao lista $($pacote.name)." }
        $esperado = $linha.Line.Split(' ')[0].ToLower()
        $obtido = (Get-FileHash -LiteralPath $arquivo -Algorithm SHA256).Hash.ToLower()
        if ($esperado -ne $obtido) { Erro 'SHA-256 divergente; o download veio corrompido.' }
        Write-Host '  SHA-256 confere'
    } else {
        Write-Host '  AVISO: release sem SHA256SUMS.txt; seguindo sem conferencia' -ForegroundColor Yellow
    }

    Passo 'Extracao'
    Expand-Archive -LiteralPath $arquivo -DestinationPath $trabalho -Force
    Get-ChildItem -LiteralPath $trabalho -Recurse | Unblock-File
    $atualizador = Get-ChildItem -LiteralPath $trabalho -Recurse -Filter 'Atualizar-Mother.cmd' | Select-Object -First 1
    if (-not $atualizador) { Erro 'Atualizar-Mother.cmd nao encontrado dentro do pacote.' }

    Passo 'Instalacao'
    & $atualizador.FullName
    exit $LASTEXITCODE
}
catch {
    Erro $_.Exception.Message
}
