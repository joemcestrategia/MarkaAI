# Guia de Conciliação de Pagamentos (PIX e Manuais)

Este documento descreve as diretrizes para a manipulação de transações financeiras e baixa de pagamentos no sistema MarkaAI, especificamente para pagamentos de serviços e agendamentos. Seu objetivo é prevenir a reintrodução de bugs de "falso adiantamento", perda de referência e falha na consolidação do Resumo Financeiro.

## 1. Passagem de `external_reference` em Gateways

**Regra de Ouro:** NUNCA gere uma transação (PIX, Cartão, Boleto) no Mercado Pago (ou outro gateway) para um agendamento sem enviar o parâmetro `external_reference` (ou `externalReference`).

**Por quê?** 
Se o aplicativo falhar, for fechado, ou o usuário trocar de aba antes que o *polling* local detecte o pagamento, o Webhook no servidor (`mpPaymentWebhook`) assumirá a responsabilidade de processar a aprovação. Sem o `external_reference` apontando para o ID do Agendamento, o Webhook não consegue vincular o pagamento à tabela `appointments`, resultando em uma transação financeira aprovada sem a respectiva baixa no sistema.

**Exemplo Correto (Flutter):**
```dart
final result = await MercadoPagoService.gerarPix(
  shopId: shopId,
  amount: amount,
  description: "Pagamento do agendamento",
  externalReference: appointment['id'], // OBRIGATÓRIO
);
```

## 2. Pagamento Integral vs. Parcial/Restante

O banco de dados usa colunas estruturais para o financeiro:
- `total_payable`: O valor final do serviço.
- `paid_amount`: O que foi efetivamente pago até agora.
- `remaining_amount`: `total_payable` - `paid_amount`.

### A Armadilha do Adiantamento (Falso Positivo)
Ao registrar um pagamento manual ou atualizar a interface, é necessário diferenciar se a transação representa a **conclusão** de um pagamento parcelado/adiantado, ou se é um **pagamento integral**.

O metadado do agendamento (`metadata`) utiliza chaves específicas para identificar quando o pagamento foi feito em duas etapas:
- `advance_payment_id`: ID da transação que pagou o sinal.
- `completion_payment_id`: ID da transação que pagou o restante.

**O Erro Comum:** Ao "Marcar como Pago" o valor *integral* de um serviço de forma manual, NÃO crie as chaves de `completion_payment_id`. Se você as criar, a UI entenderá erroneamente que o pagamento foi dividido, criando seções duplicadas de "Detalhes de Adiantamento".

**Código Correto para Pagamentos Manuais (Flutter):**
```dart
Map<String, dynamic> newMeta = Map.from(currentMeta);

if (pagoAntigo > 0.01) {
  // Já houve sinal! Então o pagamento atual é o "Restante".
  newMeta['advance_payment_id'] = currentMeta['advance_payment_id'] ?? paymentIdOriginal;
  newMeta['completion_payment_id'] = 'manual';
  newMeta['completion_payment_method'] = metodoSelecionado;
} else {
  // Pagamento INTEGRAL direto. 
  // O payment_id principal abrigará este registro e NÃO MEXEMOS nas chaves completion_.
}
```

## 3. Webhook de Confirmação (`mpPaymentWebhook`)

O Webhook deve atuar sempre de forma **Aditiva e Idempotente**.

1. **Aditivo:** Nunca assuma que o webhook representa o primeiro e único pagamento (`paid_amount = transacao_atual`). O cliente pode estar pagando o restante via PIX. Verifique se já existia um `payment_id` vinculado ao agendamento diferente do recebido. Se sim, **some** o valor e calcule o restante: `paid_amount = current_paid + transacao_atual`.
2. **Idempotente:** Se o webhook chegar duas vezes pelo gateway, garanta que ele não vai somar o valor de novo. Confira sempre se o ID da transação atual já não é o mesmo registrado no `metadata['completion_payment_id']` ou na raiz `payment_id`.

**Exemplo Correto (TypeScript / Edge Function):**
```typescript
let newPaidAmount = currentAppt?.paid_amount ?? 0;
let isSecondPayment = false;

if (currentAppt?.payment_id && currentAppt.payment_id !== paymentId.toString()) {
  isSecondPayment = true;
  const meta = currentAppt?.metadata || {};
  // Verifica duplicidade do webhook
  if (meta.completion_payment_id !== paymentId.toString()) {
    newPaidAmount += paidAmount; // Aditivo
  }
} else {
  newPaidAmount = paidAmount;
}
```

Seguindo esses padrões, a conciliação será mantida integra e sem duplicidades para o cliente e para a gestão do sistema.
