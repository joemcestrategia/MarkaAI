# 🔔 Sistema Completo de Notificações Push

## ✅ O que foi implementado:

### 1. **Serviço de Notificações** (`notification_service.dart`)
- Gerenciamento completo de tokens FCM
- Solicitação de permissões (iOS/Android)
- Salvamento automático de tokens no Firestore
- Remoção de tokens no logout
- Handlers para notificações em foreground/background/terminado

### 2. **Cloud Functions (Triggers Automáticos)**

#### 🎉 `onNewAppointment`
**Quando:** Cliente faz um novo agendamento
**Notifica:** Dono da loja
**Mensagem:** "🎉 Novo Agendamento! [Cliente] agendou [Serviço] para [Data] às [Hora]"

#### ❌ `onAppointmentCancelled`
**Quando:** Cliente cancela um agendamento
**Notifica:** Dono da loja
**Mensagem:** "❌ Agendamento Cancelado - [Cliente] cancelou o agendamento de [Serviço] marcado para [Data] às [Hora]"

#### 💰 `Pagamento Recebido` (dentro de `onAppointmentCancelled`)
**Quando:** Cliente paga um agendamento
**Notifica:** Dono da loja
**Mensagem:** "💰 Pagamento Recebido! [Cliente] pagou [Valor] pelo agendamento de [Serviço]"

#### 📝 `onClientProfileUpdate`
**Quando:** Cliente atualiza dados do perfil (nome, telefone, email)
**Notifica:** Dono da loja (que tem agendamentos futuros com esse cliente)
**Mensagem:** "📝 Cliente Atualizou Dados - [Cliente] atualizou: [campos modificados]"

### 3. **Integração no App**
- ✅ Inicialização automática quando dono faz login
- ✅ Token salvo no documento da loja (`fcm_tokens`)
- ✅ Token salvo no documento do usuário (`fcm_token`)
- ✅ Remoção automática do token no logout
- ✅ Notificações exibidas em foreground como SnackBar
- ✅ Handler de background configurado

---

## 📋 Status do Deploy:

### ✅ **Concluído:**
- Serviço de notificações Flutter
- Cloud Functions criadas
- Integração no Business Home Page
- Integração no Main.dart

### ⏳ **Aguardando (Permissões Eventarc):**
As 3 Cloud Functions de trigger falharam no primeiro deploy porque o **Eventarc Service Agent** precisa de alguns minutos para configurar as permissões.

**Erro recebido:**
```
Permission denied while using the Eventarc Service Agent. 
If you recently started to use Eventarc, it may take a few minutes 
before all necessary permissions are propagated to the Service Agent.
```

### 🔧 **Próximo Passo - VOCÊ PRECISA FAZER:**

**Aguarde 5-10 minutos** e então execute:

```bash
firebase deploy --only functions
```

Isso vai retentar o deploy das 3 funções de notificação.

---

## 🚀 Como Funciona:

### Para o Dono da Loja:

1. **Login:** Token FCM é gerado e salvo automaticamente
2. **Notificações Recebidas Quando:**
   - Cliente agenda → Notificação instantânea
   - Cliente cancela → Notificação instantânea  
   - Cliente paga → Notificação instantânea
   - Cliente atualiza perfil → Notificação instantânea

3. **No App (Foreground):** SnackBar roxo aparece com opção "VER"
4. **Fora do App:** Notificação push normal do Android/iOS
5. **Clicando na Notificação:** App abre na tela de agendamentos

### Estrutura no Firestore:

```javascript
shops/{shopId}
  fcm_tokens: ["token1", "token2", ...] // Array de tokens (suporta múltiplos dispositivos)
  fcm_updated_at: Timestamp

users/{userId}
  fcm_token: "token_atual"
  fcm_updated_at: Timestamp
```

---

## 🔍 Testando as Notificações:

### Teste 1: Novo Agendamento
1. Cliente agenda um serviço
2. Dono deve receber: "🎉 Novo Agendamento! ..."

### Teste 2: Cancelamento
1. Cliente cancela agendamento
2. Dono deve receber: "❌ Agendamento Cancelado ..."

### Teste 3: Pagamento
1. Cliente paga um agendamento
2. Dono deve receber: "💰 Pagamento Recebido! ..."

### Teste 4: Atualização de Perfil
1. Cliente muda nome/telefone/email
2. Dono (com agendamento futuro) deve receber: "📝 Cliente Atualizou Dados ..."

---

## ⚙️ Configuração de Permissões:

### Android (`android/app/src/main/AndroidManifest.xml`)
As permissões já devem estar configuradas pelo pacote `firebase_messaging`, mas verifique:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### iOS (`ios/Runner/Info.plist`)
Adicione as permissões de notificação:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>remote-notification</string>
</array>
```

---

## 🎯 Dados Enviados na Notificação:

Cada notificação inclui `data` para navegação/processamento:

```javascript
{
  type: 'new_appointment' | 'appointment_cancelled' | 'payment_received' | 'client_profile_update',
  appointmentId: 'ABC123',
  shopId: 'shop_xyz',
  clientId: 'user_789',
  // Campos extras dependendo do tipo
}
```

---

## 💡 Melhorias Futuras Possíveis:

- [ ] Notificar cliente X dias antes do agendamento
- [ ] Notificar cliente quando agendamento for confirmado pelo dono
- [ ] Sons customizados para cada tipo de notificação
- [ ] Navegação direta para a página do agendamento ao clicar
- [ ] Agrupamento de notificações (várias em uma)
- [ ] Notificações programadas (lembretes)

---

## ❓ Problemas Comuns:

### "Não estou recebendo notificações"

1. **Verifique se o token foi salvo:**
   - Firebase Console → Firestore → `shops/{seu_shop_id}`
   - Deve ter campo `fcm_tokens` com array de tokens

2. **Verifique permissões do app:**
   - Android: Configurações → Apps → MarkaAI → Notificações → Permitir
   - iOS: Configurações → Notificações → MarkaAI → Permitir

3. **Verifique se as Cloud Functions foram deployadas:**
   ```bash
   firebase functions:list
   ```
   Deve aparecer: `onNewAppointment`, `onAppointmentCancelled`, `onClientProfileUpdate`

4. **Logs das Cloud Functions:**
   ```bash
   firebase functions:log
   ```

### "Cloud Functions falharam no deploy"

Isso é normal na **primeira vez**. O Firebase precisa configurar permissões do Eventarc.

**Solução:** Aguarde 5-10 minutos e execute novamente:
```bash
firebase deploy --only functions
```

---

## 📞 Precisa de Ajuda?

Se as notificações não funcionarem após seguir todos os passos, me chame que eu te ajudo! 😊
