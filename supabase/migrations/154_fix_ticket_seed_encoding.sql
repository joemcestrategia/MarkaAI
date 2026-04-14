-- ============================================================
-- Migration 154: Fix encoding on seed ticket data
-- The original seed was inserted with broken encoding (UTF-8
-- bytes interpreted as latin1), replacing accented chars with ??
-- This updates all 15 seed tickets to correct Portuguese text.
-- ============================================================

UPDATE support_tickets SET
  title = 'Pagamento PIX não confirmado',
  description = 'Fiz um pagamento via PIX mas o status continua como pendente há 2 horas.'
WHERE ticket_number = 1;

UPDATE support_tickets SET
  title = 'Agendamento duplicado',
  description = 'O cliente aparece com dois horários no mesmo dia para o mesmo serviço.'
WHERE ticket_number = 2;

UPDATE support_tickets SET
  title = 'WhatsApp não envia confirmação',
  description = 'As mensagens de confirmação de agendamento não estão sendo enviadas pelo WhatsApp.'
WHERE ticket_number = 3;

UPDATE support_tickets SET
  title = 'Erro ao emitir NFS-e',
  description = 'Ao tentar emitir a nota fiscal, aparece erro "município não aderido".'
WHERE ticket_number = 4;

UPDATE support_tickets SET
  title = 'Não consigo acessar minha conta',
  description = 'Esqueci a senha e o e-mail de recuperação não chega.'
WHERE ticket_number = 5;

UPDATE support_tickets SET
  title = 'Como alterar plano de assinatura?',
  description = 'Quero fazer upgrade do plano Start para o Plus.'
WHERE ticket_number = 6;

UPDATE support_tickets SET
  title = 'Cartão de crédito recusado',
  description = 'Tentei pagar com cartão de crédito e dá erro "transação não autorizada".'
WHERE ticket_number = 7;

UPDATE support_tickets SET
  title = 'Horários não aparecem para clientes',
  description = 'Meus clientes dizem que não veem horários disponíveis na página de agendamento.'
WHERE ticket_number = 8;

UPDATE support_tickets SET
  title = 'Relatório financeiro zerado',
  description = 'O relatório financeiro do mês mostra R$ 0,00 mesmo tendo vários atendimentos.'
WHERE ticket_number = 9;

UPDATE support_tickets SET
  title = 'Integração WhatsApp caiu',
  description = 'A integração com WhatsApp parou de funcionar desde ontem à noite.'
WHERE ticket_number = 10;

UPDATE support_tickets SET
  title = 'Cancelar NFS-e emitida por engano',
  description = 'Emiti uma NFS-e para o cliente errado e preciso cancelar.'
WHERE ticket_number = 11;

UPDATE support_tickets SET
  title = 'Funcionário não consegue logar',
  description = 'Cadastrei um funcionário mas ele não consegue acessar o sistema.'
WHERE ticket_number = 12;

UPDATE support_tickets SET
  title = 'Sugestão: campo de observação no agendamento',
  description = 'Seria ótimo poder adicionar uma observação no agendamento para anotar preferências do cliente.'
WHERE ticket_number = 13;

UPDATE support_tickets SET
  title = 'Taxa do cartão errada',
  description = 'A taxa do cartão está sendo calculada como 5% mas deveria ser 3.5%.'
WHERE ticket_number = 14;

UPDATE support_tickets SET
  title = 'Cliente não recebe lembrete',
  description = 'Os clientes não estão recebendo o lembrete 24h antes do agendamento.'
WHERE ticket_number = 15;

-- Also fix shop_name and opened_by_name
UPDATE support_tickets SET shop_name = 'Barbearia do João', opened_by_name = 'João Silva' WHERE ticket_number = 1;
UPDATE support_tickets SET shop_name = 'Salão Beleza Pura' WHERE ticket_number = 2;
UPDATE support_tickets SET shop_name = 'Clínica Estética VIP' WHERE ticket_number = 4;
UPDATE support_tickets SET shop_name = 'Salão da Rê' WHERE ticket_number = 6;
UPDATE support_tickets SET shop_name = 'Espaço Zen Hair' WHERE ticket_number = 9;
UPDATE support_tickets SET shop_name = 'Salão Glamour', opened_by_name = 'Patricia Rocha' WHERE ticket_number = 10;
UPDATE support_tickets SET shop_name = 'Espaço Beauty' WHERE ticket_number = 14;

-- Fix ticket_messages encoding too
UPDATE ticket_messages SET body = 'Olá João, verificamos seu pagamento PIX. Pode confirmar o valor e horário da transação?' WHERE body LIKE '%Ol%Jo%o%verificamos%PIX%';
UPDATE ticket_messages SET body = 'Foi R$ 85,00 às 14:30 de hoje. O comprovante mostra confirmado.' WHERE body LIKE '%Foi R%85%14:30%';
UPDATE ticket_messages SET body = 'Identificamos que o PIX caiu na conta de outro CNPJ. Vamos estornar e reprocessar.' WHERE body LIKE '%Identificamos%PIX%CNPJ%';
UPDATE ticket_messages SET body = 'Horários reconfigurados. Pode verificar se os clientes já conseguem ver?' WHERE body LIKE '%Hor%rios%reconfigurados%';
UPDATE ticket_messages SET body = 'Nota interna: Cliente tem plano Premium, priorizar atendimento.' WHERE body LIKE '%Nota interna%Cliente tem plano%';
UPDATE ticket_messages SET body = 'Estamos investigando a integração. Parece ser um problema na API do WhatsApp Business.' WHERE body LIKE '%investigando%integra%WhatsApp Business%';
UPDATE ticket_messages SET body = 'Conseguimos restaurar a conexão. O problema era token expirado.' WHERE body LIKE '%restaurar%conex%token expirado%';
