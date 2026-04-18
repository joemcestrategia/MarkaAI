-- Migration 157: pg_cron job para limpar agendamentos pendente_pix abandonados
--
-- Um agendamento fica em 'pendente_pix' quando o cliente gera o QR Code mas
-- não conclui o pagamento. Como o status não bloqueia o slot (ver checkAvailability),
-- esses registros são apenas "fantasmas" no banco e podem ser removidos com segurança
-- após 30 minutos sem pagamento confirmado.

SELECT cron.schedule(
  'cleanup-pendente-pix',
  '*/30 * * * *',  -- executa a cada 30 minutos
  $$
    UPDATE public.appointments
    SET
      status = 'cancelado',
      updated_at = now()
    WHERE
      status = 'pendente_pix'
      AND payment_status IS DISTINCT FROM 'pago'
      AND created_at < now() - interval '30 minutes';
  $$
);
