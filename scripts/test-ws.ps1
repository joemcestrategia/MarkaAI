$headers = @{
  apikey = 'markaai2026'
  'Content-Type' = 'application/json'
}

$instanceName = 'shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9'

# 1. Delete instance
try {
  Invoke-WebRequest -Method DELETE -Uri "http://187.127.26.94:8080/instance/delete/$instanceName" -Headers @{apikey='markaai2026'} | Out-Null
} catch {}
Write-Host "Started..."

$body = '{"instanceName":"shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9","qrcode":true,"integration":"WHATSAPP-BAILEYS","websocket":{"enabled":true,"events":["QRCODE_UPDATED"]}}'

try {
    $createResp = Invoke-WebRequest -Method POST -Uri "http://187.127.26.94:8080/instance/create" -Headers $headers -Body $body
    Write-Host "Created instance."
} catch {
    Write-Host "Error creating instance: $($_.Exception.Message)"
}

# we can't easily wait on a WebSocket in pure powershell without extra libraries.
# I will write a simple Node.js script instead to test the websocket logic!
