# Resolução de Problemas: Erro `operator does not exist: text = uuid`

## Sintoma
O aplicativo ou operações diretas no Supabase falham ao inserir ou atualizar agendamentos (tabela `appointments`), retornando o erro:
`Erro: PostgrestException(message: operator does not exist: text = uuid, code: 42883...)`
(ou `uuid = text`).

## Causa Raiz
O banco de dados PostgreSQL bloqueia comparações diretas entre colunas ou valores do tipo `UUID` e do tipo `TEXT` se não houver um _cast_ explícito.
No projeto MarkaAI:
- O `id` do usuário (tabela `users` e `auth.uid()`) é **UUID**.
- As colunas de relacionamento com o usuário na tabela `appointments` (como `client_id`, `professional_id`) e na tabela `shops` (`owner_id`) são do tipo **TEXT**.

Isso gerou quebra no banco nas seguintes situações que disparam Gatilhos (Triggers) em Background:

1. **Gatilho de Dias de Trabalho** (`check_appointment_work_day_fn`):
   O código verificava permissão de dono de loja com `WHERE id = NEW.shop_id AND owner_id = v_uid`. 
   Sendo `v_uid` (vindo de `auth.uid()`) um UUID e `owner_id` um TEXT, isso quebrava.

2. **Gatilho de Desconto de Aniversário** (`handle_birthday_discount_usage_fn`):
   O código procurava o email do cliente com `WHERE id = NEW.client_id` na tabela `users`.
   Sendo `users.id` um UUID e `NEW.client_id` um TEXT, isso também quebrava a operação.

## Solução
Sempre que for necessário comparar IDs vindos da tabela `users` (UUID) com chaves estrangeiras lógicas tipo texto (`client_id`, `owner_id`, `professional_id`), é obrigatório o uso de conversão de tipos explícita (cast) com `::text`.

**Exemplos Corrigidos:**
* Em Políticas RLS ou Gatilhos:
  * ❌ Incorreto: `owner_id = auth.uid()`
  * ✅ Correto: `owner_id = auth.uid()::text`
  * ❌ Incorreto: `WHERE id = NEW.client_id` (onde `id` é UUID e `client_id` é texto)
  * ✅ Correto: `WHERE id::text = NEW.client_id`

## Migrações de Correção Aplicadas
- `210_fix_availability_rpcs_types.sql`: Corrigiu as chamadas RPC de bloqueio de horários.
- `211_fix_work_day_trigger_type.sql`: Corrigiu a comparação no trigger `check_appointment_work_day_fn`.
- `212_fix_birthday_trigger_type.sql`: Corrigiu a comparação no trigger `handle_birthday_discount_usage_fn`.
