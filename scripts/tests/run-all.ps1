$ErrorActionPreference = "Stop"

Write-Host "Iniciando a bateria de testes automatizados..." -ForegroundColor Cyan
$passed = 0
$total = 3

# Teste 1: Regressão plan-mapping
Write-Host "`n[1/3] Executando test-plan-mapping-regression.ts..." -ForegroundColor Yellow
try {
    # Usando Deno
    $p1 = Start-Process deno -ArgumentList "test", "-A", "scripts/tests/test-plan-mapping-regression.ts" -NoNewWindow -Wait -PassThru
    if ($p1.ExitCode -eq 0) {
        Write-Host "[PASS] test-plan-mapping-regression.ts" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] test-plan-mapping-regression.ts (Exit code: $($p1.ExitCode))" -ForegroundColor Red
        exit $p1.ExitCode
    }
} catch {
    Write-Host "[FAIL] Erro ao rodar test-plan-mapping-regression.ts: $_" -ForegroundColor Red
    exit 1
}

# Teste 2: Resource Missing (Stripe + Supabase)
Write-Host "`n[2/3] Executando test-resource-missing.ts..." -ForegroundColor Yellow
try {
    $p2 = Start-Process deno -ArgumentList "test", "-A", "scripts/tests/test-resource-missing.ts" -NoNewWindow -Wait -PassThru
    if ($p2.ExitCode -eq 0) {
        Write-Host "[PASS] test-resource-missing.ts" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] test-resource-missing.ts (Exit code: $($p2.ExitCode))" -ForegroundColor Red
        exit $p2.ExitCode
    }
} catch {
    Write-Host "[FAIL] Erro ao rodar test-resource-missing.ts: $_" -ForegroundColor Red
    exit 1
}

# Teste 3: Fallback Offline (Dart)
Write-Host "`n[3/3] Executando subscription_service_fallback_test.dart..." -ForegroundColor Yellow
try {
    $p3 = Start-Process flutter -ArgumentList "test", "test/subscription_service_fallback_test.dart" -NoNewWindow -Wait -PassThru
    if ($p3.ExitCode -eq 0) {
        Write-Host "[PASS] subscription_service_fallback_test.dart" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] subscription_service_fallback_test.dart (Exit code: $($p3.ExitCode))" -ForegroundColor Red
        exit $p3.ExitCode
    }
} catch {
    Write-Host "[FAIL] Erro ao rodar subscription_service_fallback_test.dart: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n-------------------------------------"
if ($passed -eq $total) {
    Write-Host "Resultado: $passed/$total passaram." -ForegroundColor Green
} else {
    Write-Host "Resultado: $passed/$total passaram." -ForegroundColor Red
}
Write-Host "-------------------------------------"
