# RLS Activation Tracking

Projeto: MarkaAI | Início: 16/06/2026

**Objetivo:** Ativar RLS uma tabela por vez, verificando se o código está preparado e testando o impacto.

---

## Status Geral

| # | Tabela | RLS Atual | Código Preparado? | Ativada? | Teste OK? | Observações |
|---|--------|-----------|-------------------|----------|-----------|-------------|
| 1 | bank_accounts | ✅ ON (mig 194) | ✅ 0 refs cliente | ✅ | ✅ 8/8 testes | Só service_role acessa |
| 2 | approved_payments | ✅ ON (mig 194) | ✅ 0 refs cliente | ✅ | ✅ 8/8 testes | Só service_role acessa |
| 3 | webhook_logs | ✅ ON (mig 194) | ✅ 0 refs cliente | ✅ | ✅ 8/8 testes | Admin pode ver logs |
| 4 | plans | ❌ OFF | ⚠️ Admin client-side | ⬜ | ⬜ | Mig 192 |
| 5 | categories | ❌ OFF | ⚠️ Admin insere sem shop_id | ⬜ | ⬜ | Mig a criar |
| 6 | financial_transactions | ✅ ON | ✅ Pronto | ✅ | ✅ Dashboard/Histórico OK | - |
| 7 | shops | ❌ OFF | ⚠️ Busca pública sem filtro | ⬜ | ⬜ | Mig 193 |
| 8 | services | ✅ ON | ✅ Pronto | ✅ | ✅ CRUD serviços, agendamento, público OK | - |
| 9 | saved_cards | ✅ ON | ✅ Pronto | ✅ | ✅ Checkout carrega, cartão salvo OK | - |
| 10 | appointments | ✅ ON | ✅ Pronto | ✅ | ✅ Criar/editar/excluir/cliente OK | - |
| 11 | employees | ✅ ON | ✅ Pronto | ✅ | ✅ CRUD equipe OK, público OK | - |

---

## Log de Atividades

### 16/06/2026
- **19:00** Criada migração `194_enable_rls_safe_tables.sql` — RLS para bank_accounts, approved_payments, webhook_logs
- **19:05** Migração aplicada com sucesso via `supabase db push`
- **19:10** Testes unitários: 8/8 passando. Nenhuma quebra
- **20:15** `financial_transactions` — RLS ativado via SQL Editor. Teste: Dashboard Financeiro e Histórico OK
- **20:30** `saved_cards` — RLS ativado. Teste: Checkout sem erro, salvamento OK
- **20:45** `employees` — RLS ativado. Teste: CRUD equipe (add/edit/remove), página pública OK
- **21:00** `services` — RLS ativado. Teste: CRUD serviços, agendamento, página pública OK
- **21:20** `appointments` — RLS ativado (4 políticas). Teste: criar/excluir como dono, histórico cliente OK
- **21:40** PAUSA — Restam: shops, plans, categories

