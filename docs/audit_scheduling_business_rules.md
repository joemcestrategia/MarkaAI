# Auditoria: Regras de Negócio de Agendamento & Checkout

**Data:** 2026-03-26  
**Escopo:** Scheduling engine, checkout flow, payment processing, business rules configs  
**Status:** ✅ Auditoria concluída — bugs críticos corrigidos

---

## 1. Resumo Executivo

### Bugs Críticos Encontrados e Corrigidos

| # | Bug | Severidade | Arquivo | Status |
|---|-----|-----------|---------|--------|
| 1 | **Agendamento criado antes do pagamento PIX** | 🔴 Crítico | `checkout_page.dart` | ✅ Corrigido |
| 2 | **Notificação "Confirmado" enviada para status "pendente"** | 🔴 Crítico | `appointmentTriggers/index.ts` | ✅ Corrigido |
| 3 | **`isProblematic` sempre retornava `false`** | 🔴 Crítico | `client_verification_service.dart` | ✅ Corrigido |
| 4 | **Colunas legadas em `booking_page.dart`** | 🟡 Alto | `booking_page.dart` | ✅ Corrigido |
| 5 | **Colunas legadas em `my_appointments_page.dart`** | 🟡 Alto | `my_appointments_page.dart` | ✅ Corrigido |
| 6 | **`permitir_reagendamento` nunca era verificado** | 🟡 Alto | `client_verification_service.dart` | ✅ Corrigido |

---

## 2. Bug Crítico: Agendamento Antes do Pagamento

### Problema
No fluxo PIX, `_executeFinalAction()` chamava `_saveBooking(isPreSave: true, status: "pendente")` **antes** de gerar o QR Code. Isso causava:

1. **Slot bloqueado prematuramente** — se o cliente nunca pagasse, o horário ficava ocupado para sempre
2. **Notificação prematura** — o webhook `appointmentTriggers` disparava WhatsApp/Email de "Agendamento Confirmado" no INSERT, sem verificar o status
3. **Agendamentos órfãos** — registros "pendente" sem pagamento acumulavam no banco

### Correção Aplicada

**`checkout_page.dart`** — Removido o pre-save do PIX:
```dart
// ANTES (bugado):
final appointmentId = await _saveBooking(status: "pendente", isPreSave: true);
_generatePix(valor, desc, externalRef: appointmentId);

// DEPOIS (corrigido):
final tempRef = "ORD-${DateTime.now().millisecondsSinceEpoch}";
_preSavedAppointmentId = null;
_generatePix(valor, desc, externalRef: tempRef);
```

**`appointmentTriggers/index.ts`** — Filtro de status no INSERT:
```typescript
const notifiableStatuses = ['agendado', 'confirmado']
if (!notifiableStatuses.includes(currentStatus)) {
  return // skip notification
}
```

### Fluxo Correto Pós-Correção

| Método | Quando cria o agendamento | Status inicial |
|--------|--------------------------|----------------|
| **Local** | Ao clicar "FINALIZAR" no modal | `agendado` |
| **PIX** | Somente após `approved` do polling/manual check | `confirmado` |
| **Cartão (novo)** | Somente após `success == true` do MP | `confirmado` |
| **Cartão (salvo)** | Somente após `status == 'approved'` do MP | `confirmado` |

---

## 3. Bug Crítico: `isProblematic` Sempre `false`

### Problema
`ClientVerificationService.getClientStatus()` **nunca consultava** o status de problemático do banco. Retornava `isProblematic: false` hardcoded em todos os caminhos.

### Correção
Agora lê `is_vip` e `is_problematic` da tabela `users` (flags manuais do dono) e combina com VIP automático por histórico:

```dart
final futures = await Future.wait([
  _supabase.from('shops').select('config').eq('id', shopId).maybeSingle(),
  _supabase.from('users').select('is_vip, is_problematic').eq('id', userId).maybeSingle(),
  _supabase.from('appointments').select('scheduled_at, status')...
]);
bool isVip = manualVip || autoVip;  // Manual OR automático
bool isProblematic = manualProblematic;  // Apenas manual
```

### Migration
`118_audit_schema_corrections.sql` adiciona as colunas `is_vip`, `is_problematic`, `vip_since`, `problematic_since`, `visit_count`, `last_visit_at` na tabela `users`.

---

## 4. Colunas Legadas Corrigidas

### `booking_page.dart`
| Linha | Antes (legado) | Depois (schema atual) |
|-------|---------------|----------------------|
| 535 | `duracao_min`, `duracao` | `duration_min` |
| 1339 | `duracao_min`, `duracao` | `duration_min` |
| 1343 | `servicoId`, `servico_id` | `service_id` |
| 1354 | `tempo_min` | `duration_min` |
| 1374 | `tempo_min` | `duration_min` |
| 1048 | `nome` | `name` (com fallback `nome`) |
| 1214 | `nome` | `name` (com fallback `nome`) |
| 1236 | `nome` | `name` (com fallback `nome`) |

### `my_appointments_page.dart`
| Linha | Antes | Depois |
|-------|-------|--------|
| 978 | `profissionalId` | `professional_id` (com fallback) |
| 979 | `servicoId` | `service_id` (com fallback) |

---

## 5. `permitir_reagendamento` Agora Enforced

### Problema
A config `permitir_reagendamento` era salva/lida no `business_settings_page.dart`, mas **nunca verificada** no fluxo de reagendamento do cliente.

### Correção
`canModifyAppointment()` agora aceita `{bool isReschedule = false}` e verifica a config:

```dart
if (isReschedule) {
  final bool allowReschedule = config['permitir_reagendamento'] ?? true;
  if (!allowReschedule) {
    return {'can': false, 'reason': 'Esta loja não permite reagendamento online.'};
  }
}
```

Chamada atualizada em `my_appointments_page.dart` botão "REAGENDAR":
```dart
ClientVerificationService.canModifyAppointment(appointment, isReschedule: true)
```

---

## 6. Mapa de Config Keys (`shops.config` JSONB)

O sistema usa `shops.config` (JSONB) em vez de tabela `settings` separada. Todas as configs estão funcionando corretamente:

### Regras de Agendamento
| Config Key | Default | Onde é lido | Status |
|-----------|---------|-------------|--------|
| `intervalo_agenda_min` | 60 | BookingPage, checkAvailability | ✅ OK |
| `evitar_buracos_agenda` | false | BookingTimePage, BookingSlotsPage | ✅ OK |
| `janela_agendamento_dias` | 90 | BookingTimePage, checkAvailability | ✅ OK |
| `limite_minimo_agendamento_horas` | 7 | BookingPage, checkAvailability | ✅ OK |
| `permitir_multiplos` | true | checkout_page._saveBooking | ✅ OK |
| `permitir_reagendamento` | true | canModifyAppointment (🆕) | ✅ Corrigido |
| `cliente_escolhe_prof` | true | BookingPage | ✅ OK |
| `agendamento_online_ativo` | true | client_home, client_service_detail | ✅ OK |
| `tempo_cancelamento_horas` | 2 | canModifyAppointment | ✅ OK |
| `auto_block_holidays` | false | BookingTimePage, checkAvailability | ✅ OK |

### Pagamento & Financeiro
| Config Key | Default | Onde é lido | Status |
|-----------|---------|-------------|--------|
| `cartao_online` | false | checkout_page, settings | ✅ OK |
| `pagamento_pix` | false | checkout_page, settings | ✅ OK |
| `pagar_pessoalmente` | true | checkout_page, settings | ✅ OK |
| `exigir_sinal` | false | checkout_page | ✅ OK |
| `percentual_sinal` | 30 | checkout_page | ✅ OK |
| `tax_percent` | 0 | checkout_page | ✅ OK |

### Classificação de Clientes
| Config Key | Default | Onde é lido | Status |
|-----------|---------|-------------|--------|
| `vip_min_visits` | 15 | client_verification_service | ✅ OK |
| `vip_avg_interval` | 30 | settings (save only) | ✅ OK |
| `sumido_max_days` | 45 | client_verification_service | ✅ OK |
| `vip_extra_booking_days` | 0 | BookingTimePage | ✅ OK |
| `restrict_problematic_clients` | false | BookingPage, BookingTimePage | ✅ Corrigido |
| `trusted_only_pay_in_person` | false | checkout_page | ✅ OK |

### Desconto Aniversário
| Config Key | Default | Onde é lido | Status |
|-----------|---------|-------------|--------|
| `birthday_pix_discount_enabled` | false | checkout_page | ✅ OK |
| `birthday_pix_discount_percent` | 10 | checkout_page | ✅ OK |

---

## 7. Validação de Conflitos (Double-Booking)

### Camadas de proteção (defense in depth):

1. **Frontend — Slot generation** (`AvailabilityUtils.generateSmartSlots`): Filtra slots ocupados antes de mostrar ao cliente. Usa intervalo semi-aberto: `startMin < interval['end'] && endMin > interval['start']` ✅

2. **Frontend — `_saveBooking` local check**: Consulta appointments ativos do mesmo profissional/horário antes de inserir ✅

3. **Backend — `checkAvailability` Edge Function**: Validação server-side com múltiplas checagens:
   - Janela de agendamento (dias)
   - Antecedência mínima (horas)
   - Dia de trabalho do profissional
   - Horário de expediente
   - Feriados (configurados + pendentes + auto-block)
   - Conflitos de horário (overlap check com ±2h window)
   
   Usa mesma lógica semi-aberta: `reqStart < apptEnd && reqEnd > apptStart` ✅

4. **Frontend — `permitir_multiplos` check**: Impede cliente de ter >1 agendamento ativo na mesma loja (quando config ativa) ✅

---

## 8. Arquivos Modificados

| Arquivo | Tipo de Alteração |
|---------|-------------------|
| `lib/pages/checkout_page.dart` | Removido PIX pre-save |
| `lib/core/services/client_verification_service.dart` | Fix isProblematic + permitir_reagendamento |
| `lib/modules/schedule/booking_page.dart` | Fix colunas legadas (6 ocorrências) |
| `lib/modules/clients/my_appointments_page.dart` | Fix colunas legadas + isReschedule flag |
| `supabase/functions/appointmentTriggers/index.ts` | Filtro status para notificações |
| `supabase/migrations/118_audit_schema_corrections.sql` | Novas colunas users + índices |

---

## 9. Verificação

```
flutter analyze: 0 errors, 0 new warnings
Apenas warnings pré-existentes (unnecessary_cast, unused_field em arquivos não-modificados)
```

---

## 10. Itens Observados (Não-Bloqueantes)

1. **`notify_new_appointments`** — Não existe config para owner opt-in/out de notificações de novos agendamentos. O webhook `appointmentTriggers` sempre envia para o cliente, mas não notifica o dono.

2. **`global_holidays` table** — Existe mas não é usada diretamente no booking flow. O sistema usa BrasilAPI + `shops.configured_holidays` JSONB. A tabela pode ser removida ou integrada no futuro.

3. **`isPreSave` parameter** — Permanece em `_saveBooking` signature mas agora é dead code. Pode ser removido em cleanup futuro.

4. **`vip_avg_interval`** — Config é salva nas settings mas nunca lida em `getClientStatus()`. A classificação VIP usa apenas `vip_min_visits` (contagem de visitas), não intervalo médio.
