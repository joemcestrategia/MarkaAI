# MarkaAI Cloud Functions - Notification System

Sistema de notificações automáticas para lembretes de agendamentos.

## Setup

### 1. Install Dependencies

```bash
cd functions
npm install
```

### 2. Configure Email Service

#### Option A: Gmail SMTP
```bash
firebase functions:config:set email.user="your-gmail@gmail.com"
firebase functions:config:set email.password="your-app-password"
```

**Para criar uma App Password no Gmail:**
1. Acesse https://myaccount.google.com/security
2. Ative autenticação de 2 fatores
3. Vá em "App passwords"
4. Gere uma senha para "Mail"

#### Option B: SendGrid (Recomendado)
1. Crie conta em https://sendgrid.com (gratuito até 100 emails/dia)
2. Gere API key
3. Configure:
```bash
firebase functions:config:set sendgrid.apikey="YOUR_SENDGRID_API_KEY"
```

### 3. Deploy Functions

```bash
firebase deploy --only functions
```

## Functions

### `checkUpcomingAppointments`
- **Tipo:** Scheduled (Cron)
- **Schedule:** Every day at 9:00 AM (Brazil timezone)
- **Ação:** Verifica agendamentos nos próximos 7 dias e envia lembretes conforme configurado

### `testNotificationSystem`
- **Tipo:** Callable
- **Uso:** Teste manual do sistema
- **Como chamar:**
```dart
final callable = FirebaseFunctions.instance.httpsCallable('testNotificationSystem');
await callable.call();
```

## Notification Logic

1. **Daily Check**: Função roda todo dia às 9h
2. **Query**: Busca agendamentos futuros (1-7 dias)
3. **For each appointment:**
   - Verifica se loja tem lembretes ativados
   - Verifica preferências do cliente
   - Calcula dias até agendamento
   - Se = reminder_days, envia email + push
4. **Mark as sent**: Marca `notification_sent = true`
5. **Log**: Cria registro em `notification_logs`

## Data Model

### appointments
```json
{
  "notification_sent": false,
  "notification_sent_at": null,
  "reminder_days_before": 3
}
```

### users
```json
{
  "notification_preferences": {
    "email_enabled": true,
    "push_enabled": true,
    "reminder_days_before": 3
  },
  "fcmToken": "token-here"
}
```

### shops
```json
{
  "notification_settings": {
    "send_reminders": true,
    "default_reminder_days": 3,
    "email_template": "default"
  }
}
```

### notification_logs (NEW)
```json
{
  "appointment_id": "string",
  "client_id": "string",
  "shop_id": "string",
  "email_sent": true,
  "push_sent": true,
  "sent_at": "Timestamp",
  "status": "sent | failed",
  "error_message": "string?"
}
```

## Testing

### 1. Local Test
```bash
npm run serve
```

### 2. Manual Trigger
No app, chame:
```dart
final callable = FirebaseFunctions.instance.httpsCallable('testNotificationSystem');
final result = await callable.call();
print(result.data);
```

### 3. Create Test Appointment
1. Crie agendamento para daqui 3 dias
2. Aguarde execução das 9h
3. Ou chame `testNotificationSystem`
4. Verifique email e push notification

## Cost Estimate

- **Firebase Functions**: ~$0.0000004 per invocation
- **Sendgrid Free**: 100 emails/day
- **FCM Push**: Unlimited (free)

**Total:** Praticamente GRÁTIS para <100 emails/dia

## Troubleshooting

### Email não enviado
- Verifique configuração: `firebase functions:config:get`
- Se Gmail: verifique app password
- Se SendGrid: verifique API key e quota

### Push não recebido
- Verifique se `fcmToken` existe no user
- Verifique permissões de notificação no app
- Check logs: `firebase functions:log`

### Logs
```bash
firebase functions:log
```

## Future Enhancements
- [ ] Templates de email customizáveis
- [ ] Múltiplos lembretes (7d + 1d)
- [ ] SMS via Twilio
- [ ] WhatsApp via Twilio/Meta API
- [ ] A/B testing de templates
