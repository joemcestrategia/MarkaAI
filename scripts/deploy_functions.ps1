# Script para deploy das Edge Functions do MarkaAI com as configurações corretas

# 1. Mercado Pago Callback (Pública - Importante para OAuth)
Write-Host "Realizando deploy da mercadopagoCallback..." -ForegroundColor Cyan
supabase functions deploy mercadopagoCallback --no-verify-jwt

# 2. Outras funções que podem ser deployadas normalmente
# Write-Host "Realizando deploy de outras funções..." -ForegroundColor Cyan
# supabase functions deploy nome-da-funcao

Write-Host "Deploy concluído!" -ForegroundColor Green
