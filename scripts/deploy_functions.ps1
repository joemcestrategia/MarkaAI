# Script para deploy das Edge Functions do MarkaAI com as configurações corretas

# 1. Mercado Pago Callback (Pública - Importante para OAuth)
Write-Host "Realizando deploy da mercadopagoCallback..." -ForegroundColor Cyan
supabase functions deploy mercadopagoCallback --no-verify-jwt

# 2. PIX Payment (sem verificação de JWT para evitar erro 401 Invalid JWT)
Write-Host "Realizando deploy da createPixPayment..." -ForegroundColor Cyan
supabase functions deploy createPixPayment --no-verify-jwt

# 3. Payment Status (sem verificação de JWT para polling de status)
Write-Host "Realizando deploy da getPaymentStatus..." -ForegroundColor Cyan
supabase functions deploy getPaymentStatus --no-verify-jwt

# 4. Delete User Account (JWT validado internamente via getUser)
Write-Host "Realizando deploy da deleteUserAccount..." -ForegroundColor Cyan
supabase functions deploy deleteUserAccount --no-verify-jwt

Write-Host "Deploy concluído!" -ForegroundColor Green
