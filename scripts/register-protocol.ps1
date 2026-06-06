# Script para Registrar o Protocolo Deep Link do MarkaAI no Windows
# Este script registra o esquema 'markaai://' para que o login do Google funcione no Windows.

$protocol = "markaai"
$executableName = "markaai.exe"

# Tenta encontrar o executável na pasta de build (Debug ou Release)
$currentDir = Get-Location
$possiblePaths = @(
    "$currentDir\build\windows\x64\runner\Debug\$executableName",
    "$currentDir\build\windows\x64\runner\Release\$executableName",
    "$currentDir\build\windows\runner\Debug\$executableName",
    "$currentDir\build\windows\runner\Release\$executableName"
)

$exePath = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $exePath = $path
        break
    }
}

if ($null -eq $exePath) {
    Write-Host "ERRO: Nao foi possivel encontrar o executavel $executableName na pasta build." -ForegroundColor Red
    Write-Host "Certifique-se de que voce ja rodou 'flutter run -d windows' ou 'flutter build windows' pelo menos uma vez." -ForegroundColor Yellow
    exit
}

Write-Host "Configurando protocolo '$protocol' para o executavel:" -ForegroundColor Cyan
Write-Host $exePath -ForegroundColor White

# Caminho no Registro (HKCU para não precisar de Admin em alguns casos, mas idealmente HKCR)
$registryPath = "HKCU:\Software\Classes\$protocol"

if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

Set-ItemProperty -Path $registryPath -Name "(Default)" -Value "URL:$protocol Protocol"
Set-ItemProperty -Path $registryPath -Name "URL Protocol" -Value ""

$commandPath = "$registryPath\shell\open\command"
    New-Item -Path $commandPath -Force | Out-Null

$commandValue = "`"$exePath`" `"%1`""
Set-ItemProperty -Path $commandPath -Name "(Default)" -Value $commandValue

Write-Host "`nSUCESSO! O protocolo '$protocol' foi registrado com exito." -ForegroundColor Green
Write-Host "Agora o login do Google devera conseguir retornar o token para o seu app." -ForegroundColor White
Write-Host "Nota: Se voce mover o projeto de pasta, precisara rodar este script novamente." -ForegroundColor Gray
