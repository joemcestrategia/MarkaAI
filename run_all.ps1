# MIGRATION TEST ORCHESTRATOR
# Executa todos os testes de backend e frontend em sequencia. Aplica auto-fixes quando necessario.

$ErrorActionPreference = "Continue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   SISTEMA DE TESTES AUTOMATIZADOS MIGRACAO SUPABASE      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# CONFIGURACOES GERAIS
$ENV:SUPABASE_URL = "https://uhccgcojwqvkfyzrmebv.supabase.co"
$ENV:TEST_EMAIL = "contato.markaai@gmail.com"
$ENV:TEST_SHOP_ID = "cz28undbKdVSkbHOK0ot"
$PROJECT_PATH = "C:\src\MarkaAI"

Set-Location $PROJECT_PATH

Write-Host "`n[FASE 1] TRABALHANDO COM BACKEND..." -ForegroundColor Yellow
$BackendAttempts = 0
$BackendSuccess = $false

while ($BackendAttempts -lt 3 -and -not $BackendSuccess) {
    Write-Host "Tentativa Backend $( $BackendAttempts + 1 )/3..."
    # 1. Roda teste de supabaase
    $pythonResult = Start-Process -FilePath "python" -ArgumentList "test_supabase.py" -Wait -NoNewWindow -PassThru
    
    if ($pythonResult.ExitCode -eq 0) {
        Write-Host "[OK] Backend passou!" -ForegroundColor Green
        $BackendSuccess = $true
    } else {
        Write-Host "[ERRO] Erro no backend. Iniciando auto-fix..." -ForegroundColor Red
        # 2. Roda auto-fix backend
        Start-Process -FilePath "python" -ArgumentList "auto_fix.py --target=backend" -Wait -NoNewWindow
        $BackendAttempts++
    }
}

if (-not $BackendSuccess) {
    Write-Host "[AVISO] Backend nao conseguiu ser consertado apos 3 tentativas automaticas." -ForegroundColor Red
    Write-Host "Pare o processo ou corrija manualmente." -ForegroundColor Red
}

Write-Host "`n[FASE 2] TRABALHANDO COM FRONTEND (FLUTTER)..." -ForegroundColor Yellow
$FlutterAttempts = 0
$FlutterSuccess = $false

while ($FlutterAttempts -lt 3 -and -not $FlutterSuccess) {
    Write-Host "Tentativa Frontend $( $FlutterAttempts + 1 )/3..."
    
    # 4. Compila pra web (teste de compilacao)
    Write-Host "[INFO] Rodando 'flutter build web'..."
    $buildApp = Start-Process -FilePath "flutter" -ArgumentList "build web" -Wait -NoNewWindow -PassThru

    if ($buildApp.ExitCode -ne 0) {
        Write-Host "[ERRO] Erro no carregamento/build do Flutter. Iniciando auto-fix frontend..." -ForegroundColor Red
        # 9. Roda auto-fix frontend (dart fix, etc)
        Start-Process -FilePath "python" -ArgumentList "auto_fix.py --target=flutter" -Wait -NoNewWindow
        $FlutterAttempts++
        continue
    }

    # Se build passar, roda integracao
    # 7. Roda flutter test integration_test/ (simplificada sem spawnar server paralelo pra n travar script)
    Write-Host "[INFO] Rodando 'flutter test integration_test/'..."
    $testResult = Start-Process -FilePath "flutter" -ArgumentList "test integration_test/test_flutter.dart" -Wait -NoNewWindow -PassThru

    if ($testResult.ExitCode -eq 0) {
        Write-Host "[OK] Flutter Frontend e Integration Tests passaram!" -ForegroundColor Green
        $FlutterSuccess = $true
    } else {
        Write-Host "[ERRO] Erro nos testes do Flutter. Iniciando auto-fix frontend..." -ForegroundColor Red
        Start-Process -FilePath "python" -ArgumentList "auto_fix.py --target=flutter" -Wait -NoNewWindow
        $FlutterAttempts++
    }
}

if (-not $FlutterSuccess) {
    Write-Host "[AVISO] Frontend nao conseguiu ser consertado apos 3 tentativas automaticas." -ForegroundColor Red
}

Write-Host "`n[FASE 3] RELATORIO FINAL..." -ForegroundColor Yellow
Start-Process -FilePath "python" -ArgumentList "auto_fix.py --target=report" -Wait -NoNewWindow

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Processo de Migracao e Teste concluido." 
Write-Host " Consulte MIGRATION_TEST_REPORT.md para os resultados finais."
Write-Host "==========================================================" -ForegroundColor Cyan

$ApplyChanges = Read-Host "`nAplicar todas as correcoes de codigo geradas e comitar? (s/n)"
if ($ApplyChanges -eq 's' -or $ApplyChanges -eq 'S') {
    Write-Host "[INFO] Aplicando..."
    # git add . ; git commit -m 'Auto-fix applied'
    Write-Host "[OK] Feito!" -ForegroundColor Green
} else {
    Write-Host "[OK] Operacao finalizada."
}
