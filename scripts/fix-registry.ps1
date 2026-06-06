$exePath = "C:\src\MarkaAI\build\windows\x64\runner\Debug\MarkaAI.exe"
$registryPath = "HKCU:\Software\Classes\markaai\shell\open\command"
$value = "`"$exePath`" `"%1`""

if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Recursive -Force
}

Set-ItemProperty -Path $registryPath -Name "(Default)" -Value $value
Write-Host "Registro atualizado para: $value"
