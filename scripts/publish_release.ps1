$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Iniciando Lançamento v1.8.18 (OTA + Web)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Build APK Release
Write-Host "`n[1/5] Compilando APK Release para Android..." -ForegroundColor Yellow
flutter build apk --release
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkPath)) {
    Write-Error "Arquivo APK nao encontrado em $apkPath"
    exit 1
}
Write-Host "APK gerado com sucesso: $apkPath" -ForegroundColor Green

# 2. Build Web Release
Write-Host "`n[2/5] Compilando Web Release..." -ForegroundColor Yellow
flutter build web --release
if (-not (Test-Path "build\web\index.html")) {
    Write-Error "Compilacao Web falhou (index.html nao encontrado)."
    exit 1
}
Write-Host "Web compilada com sucesso." -ForegroundColor Green

# 3. Deploy no Firebase Hosting
Write-Host "`n[3/5] Fazendo deploy no Firebase Hosting..." -ForegroundColor Yellow
firebase deploy --only hosting
Write-Host "Deploy no Firebase Hosting concluido." -ForegroundColor Green

# 4. Criando Release no GitHub com Upload do APK
Write-Host "`n[4/5] Criando release v1.8.18 no GitHub e fazendo upload do APK..." -ForegroundColor Yellow
$changelog = "Nova categoria Trancistas com icone exclusivo na vitrine, novo menu de perfil moderno em bottom sheet, melhorias visuais na splash screen e correcoes de layout e estabilidade."
gh release create v1.8.18 $apkPath --title "v1.8.18" --notes $changelog
Write-Host "Release v1.8.18 criada no GitHub com sucesso." -ForegroundColor Green

# 5. Inserindo nova versao no Supabase
Write-Host "`n[5/5] Registrando nova versao no Supabase (app_versions)..." -ForegroundColor Yellow
$supabaseUrl = "https://uhccgcojwqvkfyzrmebv.supabase.co"
$serviceKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Mzk2NjA0OCwiZXhwIjoyMDg5NTQyMDQ4fQ.puyVR8ZfHb6kK0rZzIAEh99MscSFTBmiRJnDGug_js4"

$headers = @{
    "apikey"        = $serviceKey
    "Authorization" = "Bearer $serviceKey"
    "Content-Type"  = "application/json"
    "Prefer"        = "return=representation"
}

$body = @{
    platform     = "android"
    version_name = "1.8.18"
    version_code = 20
    apk_url      = "https://github.com/joemcestrategia/MarkaAI/releases/download/v1.8.18/app-release.apk"
    changelog    = $changelog
    force_update = $false
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/app_versions" -Method Post -Headers $headers -Body $body
Write-Host "Versao registrada no Supabase com sucesso:" -ForegroundColor Green
$response | ConvertTo-Json

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Lançamento v1.8.18 Finalizado com Sucesso!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
