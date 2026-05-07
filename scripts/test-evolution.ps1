$headers = @{
  apikey = 'markaai2026'
  'Content-Type' = 'application/json'
}

$instanceName = 'shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9'

# 1. Deletar instância existente
Write-Host "1. Deletando instancia..."
try {
  $r = Invoke-WebRequest -Method DELETE -Uri "http://187.127.26.94:8080/instance/delete/$instanceName" -Headers @{apikey='markaai2026'}
  Write-Host $r.Content
} catch { Write-Host "Aviso delete: $($_.Exception.Message)"}

Start-Sleep -Seconds 3

# 2. Criar nova instância
Write-Host "`n2. Criando instancia..."
$body = '{"instanceName":"shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9","qrcode":true,"integration":"WHATSAPP-BAILEYS"}'
$createResp = Invoke-WebRequest -Method POST -Uri "http://187.127.26.94:8080/instance/create" -Headers $headers -Body $body
Write-Host $createResp.Content

# 3. Aguardar 10 segundos para o Baileys inicializar
Write-Host "`n3. Aguardando 10 segundos para Baileys inicializar..."
Start-Sleep -Seconds 10

# 4. Verificar estado
Write-Host "`n4. Estado da instancia:"
$stateResp = Invoke-WebRequest -Uri "http://187.127.26.94:8080/instance/connectionState/$instanceName" -Headers @{apikey='markaai2026'}
Write-Host $stateResp.Content

# 5. Tentar connect
Write-Host "`n5. Connect:"
$connectResp = Invoke-WebRequest -Uri "http://187.127.26.94:8080/instance/connect/$instanceName" -Headers @{apikey='markaai2026'}
Write-Host "Tamanho da resposta: $($connectResp.Content.Length) chars"
Write-Host $connectResp.Content.Substring(0, [Math]::Min(500, $connectResp.Content.Length))
