-- =============================================================================
-- 151_create_support_tickets_system.sql
-- Sistema de Tickets de Suporte (MarkaAI)
--
-- ATENÇÃO: shop_id é TEXT (compatível com public.shops(id)).
-- Admin check usa public.users WHERE role = 'admin' (sem tabela admin_users).
-- =============================================================================

-- =============================================================================
-- 1. TABELAS
-- =============================================================================

-- 1a. support_tickets
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_number     SERIAL UNIQUE NOT NULL,
  title             TEXT NOT NULL,
  description       TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open','in_progress','waiting_client','resolved','closed')),
  priority          TEXT NOT NULL DEFAULT 'medium'
                    CHECK (priority IN ('critical','high','medium','low')),
  category          TEXT NOT NULL
                    CHECK (category IN ('scheduling','payment','whatsapp','nfse','account','other')),
  source            TEXT NOT NULL DEFAULT 'client_portal'
                    CHECK (source IN ('client_portal','manual','email','whatsapp')),
  shop_id           TEXT REFERENCES public.shops(id) ON DELETE SET NULL,
  shop_name         TEXT,
  opened_by_user_id UUID NOT NULL,
  opened_by_name    TEXT NOT NULL,
  reporter_email    TEXT,
  assigned_to       UUID REFERENCES public.users(id) ON DELETE SET NULL,
  sla_deadline      TIMESTAMPTZ,
  resolved_at       TIMESTAMPTZ,
  closed_at         TIMESTAMPTZ,
  last_reply_at     TIMESTAMPTZ,
  last_reply_by     TEXT CHECK (last_reply_by IN ('client','support')),
  has_unread_admin  BOOLEAN DEFAULT true,
  has_unread_client BOOLEAN DEFAULT false,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- 1b. ticket_messages
CREATE TABLE IF NOT EXISTS public.ticket_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id    UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  author_id    UUID NOT NULL,
  author_name  TEXT NOT NULL,
  author_role  TEXT NOT NULL CHECK (author_role IN ('client','support','admin')),
  body         TEXT NOT NULL,
  is_internal  BOOLEAN DEFAULT false,
  attachments  JSONB DEFAULT '[]',
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- 1c. ticket_history
CREATE TABLE IF NOT EXISTS public.ticket_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id   UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  actor_name  TEXT NOT NULL,
  actor_role  TEXT NOT NULL CHECK (actor_role IN ('client','support','admin','system')),
  action      TEXT NOT NULL,
  old_value   TEXT,
  new_value   TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- 1d. ticket_tags
CREATE TABLE IF NOT EXISTS public.ticket_tags (
  id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name  TEXT NOT NULL UNIQUE,
  color TEXT NOT NULL DEFAULT '#888'
);

-- 1e. ticket_tag_links
CREATE TABLE IF NOT EXISTS public.ticket_tag_links (
  ticket_id UUID REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  tag_id    UUID REFERENCES public.ticket_tags(id) ON DELETE CASCADE,
  PRIMARY KEY (ticket_id, tag_id)
);

-- =============================================================================
-- 2. INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_support_tickets_ticket_number    ON public.support_tickets(ticket_number);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status           ON public.support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_priority         ON public.support_tickets(priority);
CREATE INDEX IF NOT EXISTS idx_support_tickets_shop_id          ON public.support_tickets(shop_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned_to      ON public.support_tickets(assigned_to);
CREATE INDEX IF NOT EXISTS idx_support_tickets_sla_deadline     ON public.support_tickets(sla_deadline);
CREATE INDEX IF NOT EXISTS idx_support_tickets_has_unread_admin ON public.support_tickets(has_unread_admin);
CREATE INDEX IF NOT EXISTS idx_support_tickets_opened_by        ON public.support_tickets(opened_by_user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created_at       ON public.support_tickets(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ticket_messages_ticket_id  ON public.ticket_messages(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_messages_created_at ON public.ticket_messages(created_at);

CREATE INDEX IF NOT EXISTS idx_ticket_history_ticket_id ON public.ticket_history(ticket_id);

-- =============================================================================
-- 3. RLS — ENABLE
-- =============================================================================
ALTER TABLE public.support_tickets  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_messages  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_history   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_tags      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_tag_links ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- 4. RLS POLICIES — support_tickets
-- =============================================================================

-- Clients: see only their own tickets
CREATE POLICY "client_select_own_tickets"
  ON public.support_tickets FOR SELECT TO authenticated
  USING (opened_by_user_id = auth.uid());

-- Clients: create tickets linked to their shop
CREATE POLICY "client_insert_ticket"
  ON public.support_tickets FOR INSERT TO authenticated
  WITH CHECK (
    opened_by_user_id = auth.uid()
    AND shop_id IN (SELECT id FROM public.shops WHERE owner_id::text = auth.uid()::text)
  );

-- Admin/Support: full access
CREATE POLICY "admin_full_access_tickets"
  ON public.support_tickets FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- =============================================================================
-- 5. RLS POLICIES — ticket_messages
-- =============================================================================

-- Clients: see messages from own tickets, EXCLUDING internal notes
CREATE POLICY "client_select_messages"
  ON public.ticket_messages FOR SELECT TO authenticated
  USING (
    is_internal = false
    AND ticket_id IN (
      SELECT id FROM public.support_tickets WHERE opened_by_user_id = auth.uid()
    )
  );

-- Clients: send messages in their own tickets (never internal)
CREATE POLICY "client_insert_message"
  ON public.ticket_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND is_internal = false
    AND author_role = 'client'
    AND ticket_id IN (
      SELECT id FROM public.support_tickets WHERE opened_by_user_id = auth.uid()
    )
  );

-- Admin/Support: full access (including internal notes)
CREATE POLICY "admin_full_access_messages"
  ON public.ticket_messages FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- =============================================================================
-- 6. RLS POLICIES — ticket_history
-- =============================================================================

-- Clients: see history of own tickets
CREATE POLICY "client_select_history"
  ON public.ticket_history FOR SELECT TO authenticated
  USING (
    ticket_id IN (
      SELECT id FROM public.support_tickets WHERE opened_by_user_id = auth.uid()
    )
  );

-- Admin: full access
CREATE POLICY "admin_full_access_history"
  ON public.ticket_history FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- =============================================================================
-- 7. RLS POLICIES — ticket_tags & ticket_tag_links
-- =============================================================================

-- Tags: readable by all authenticated, writable by admin
CREATE POLICY "authenticated_read_tags"
  ON public.ticket_tags FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "admin_manage_tags"
  ON public.ticket_tags FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- Tag links: admin only
CREATE POLICY "admin_manage_tag_links"
  ON public.ticket_tag_links FOR ALL TO authenticated
  USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- Client can see tags on own tickets
CREATE POLICY "client_select_tag_links"
  ON public.ticket_tag_links FOR SELECT TO authenticated
  USING (
    ticket_id IN (
      SELECT id FROM public.support_tickets WHERE opened_by_user_id = auth.uid()
    )
  );

-- =============================================================================
-- 8. TRIGGERS
-- =============================================================================

-- 8a. Auto-set SLA deadline on insert
CREATE OR REPLACE FUNCTION public.fn_set_sla_deadline()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.sla_deadline IS NULL THEN
    NEW.sla_deadline := CASE NEW.priority
      WHEN 'critical' THEN now() + INTERVAL '2 hours'
      WHEN 'high'     THEN now() + INTERVAL '8 hours'
      WHEN 'medium'   THEN now() + INTERVAL '24 hours'
      WHEN 'low'      THEN now() + INTERVAL '72 hours'
      ELSE now() + INTERVAL '24 hours'
    END;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sla_deadline ON public.support_tickets;
CREATE TRIGGER trg_sla_deadline
  BEFORE INSERT ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_sla_deadline();

-- 8b. Auto-set priority based on category (if not explicitly set)
CREATE OR REPLACE FUNCTION public.fn_set_default_priority()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.priority IS NULL OR NEW.priority = 'medium' THEN
    NEW.priority := CASE NEW.category
      WHEN 'payment' THEN 'high'
      WHEN 'nfse'    THEN 'high'
      WHEN 'account' THEN 'high'
      WHEN 'scheduling' THEN 'medium'
      WHEN 'whatsapp'   THEN 'medium'
      WHEN 'other'      THEN 'low'
      ELSE 'medium'
    END;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_default_priority ON public.support_tickets;
CREATE TRIGGER trg_default_priority
  BEFORE INSERT ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_default_priority();

-- 8c. Auto-update updated_at
CREATE OR REPLACE FUNCTION public.fn_support_ticket_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_support_ticket_updated_at ON public.support_tickets;
CREATE TRIGGER trg_support_ticket_updated_at
  BEFORE UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.fn_support_ticket_updated_at();

-- 8d. Record history on field changes
CREATE OR REPLACE FUNCTION public.fn_ticket_history()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
    VALUES (NEW.id, 'Sistema', 'system', 'Status alterado', OLD.status, NEW.status);
  END IF;
  IF OLD.priority IS DISTINCT FROM NEW.priority THEN
    INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
    VALUES (NEW.id, 'Sistema', 'system', 'Prioridade alterada', OLD.priority, NEW.priority);
  END IF;
  IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN
    INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
    VALUES (NEW.id, 'Sistema', 'system', 'Atribuição alterada', OLD.assigned_to::TEXT, NEW.assigned_to::TEXT);
  END IF;
  IF OLD.category IS DISTINCT FROM NEW.category THEN
    INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
    VALUES (NEW.id, 'Sistema', 'system', 'Categoria alterada', OLD.category, NEW.category);
  END IF;
  -- Track resolved_at and closed_at
  IF NEW.status = 'resolved' AND OLD.status != 'resolved' THEN
    NEW.resolved_at := now();
  END IF;
  IF NEW.status = 'closed' AND OLD.status != 'closed' THEN
    NEW.closed_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ticket_history ON public.support_tickets;
CREATE TRIGGER trg_ticket_history
  AFTER UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.fn_ticket_history();

-- 8e. Update resolved_at / closed_at on status change (BEFORE trigger for column mutation)
CREATE OR REPLACE FUNCTION public.fn_ticket_status_timestamps()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'resolved' AND (OLD.status IS DISTINCT FROM 'resolved') THEN
    NEW.resolved_at := now();
  END IF;
  IF NEW.status = 'closed' AND (OLD.status IS DISTINCT FROM 'closed') THEN
    NEW.closed_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ticket_status_timestamps ON public.support_tickets;
CREATE TRIGGER trg_ticket_status_timestamps
  BEFORE UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.fn_ticket_status_timestamps();

-- 8f. Update last_reply_at, last_reply_by, and unread flags on new message
CREATE OR REPLACE FUNCTION public.fn_ticket_last_reply()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.support_tickets SET
    last_reply_at     = NEW.created_at,
    last_reply_by     = CASE WHEN NEW.author_role = 'client' THEN 'client' ELSE 'support' END,
    has_unread_admin  = CASE WHEN NEW.author_role = 'client' THEN true ELSE has_unread_admin END,
    has_unread_client = CASE WHEN NEW.author_role IN ('support','admin') AND NEW.is_internal = false THEN true ELSE has_unread_client END
  WHERE id = NEW.ticket_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ticket_last_reply ON public.ticket_messages;
CREATE TRIGGER trg_ticket_last_reply
  AFTER INSERT ON public.ticket_messages
  FOR EACH ROW EXECUTE FUNCTION public.fn_ticket_last_reply();

-- =============================================================================
-- 9. ENABLE REALTIME
-- =============================================================================
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'support_tickets realtime: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.ticket_messages;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'ticket_messages realtime: %', SQLERRM;
END $$;

-- =============================================================================
-- 10. SEED DATA (15 varied tickets with messages)
-- =============================================================================

-- Use a fixed set of UUIDs for the seed data so it's reproducible
DO $$
DECLARE
  -- Ticket UUIDs
  t1  UUID := 'a0000001-0000-0000-0000-000000000001';
  t2  UUID := 'a0000001-0000-0000-0000-000000000002';
  t3  UUID := 'a0000001-0000-0000-0000-000000000003';
  t4  UUID := 'a0000001-0000-0000-0000-000000000004';
  t5  UUID := 'a0000001-0000-0000-0000-000000000005';
  t6  UUID := 'a0000001-0000-0000-0000-000000000006';
  t7  UUID := 'a0000001-0000-0000-0000-000000000007';
  t8  UUID := 'a0000001-0000-0000-0000-000000000008';
  t9  UUID := 'a0000001-0000-0000-0000-000000000009';
  t10 UUID := 'a0000001-0000-0000-0000-000000000010';
  t11 UUID := 'a0000001-0000-0000-0000-000000000011';
  t12 UUID := 'a0000001-0000-0000-0000-000000000012';
  t13 UUID := 'a0000001-0000-0000-0000-000000000013';
  t14 UUID := 'a0000001-0000-0000-0000-000000000014';
  t15 UUID := 'a0000001-0000-0000-0000-000000000015';
  -- Fake user UUID for seed (should match an existing admin or test user)
  fake_user UUID := '00000000-0000-0000-0000-000000000099';
BEGIN
  -- Only seed if table is empty
  IF (SELECT count(*) FROM public.support_tickets) > 0 THEN
    RAISE NOTICE 'support_tickets already has data, skipping seed';
    RETURN;
  END IF;

  -- Insert 15 tickets with varied statuses, priorities, categories, and sources
  INSERT INTO public.support_tickets (id, title, description, status, priority, category, source, shop_id, shop_name, opened_by_user_id, opened_by_name, reporter_email, has_unread_admin, has_unread_client, created_at) VALUES
    (t1,  'Pagamento PIX não confirmado', 'Fiz um pagamento via PIX mas o status continua como pendente há 2 horas.', 'open', 'high', 'payment', 'client_portal', NULL, 'Barbearia do João', fake_user, 'João Silva', 'joao@email.com', true, false, now() - INTERVAL '2 hours'),
    (t2,  'Agendamento duplicado', 'O cliente aparece com dois horários no mesmo dia para o mesmo serviço.', 'in_progress', 'medium', 'scheduling', 'client_portal', NULL, 'Salão Beleza Pura', fake_user, 'Maria Santos', 'maria@email.com', false, false, now() - INTERVAL '1 day'),
    (t3,  'WhatsApp não envia confirmação', 'As mensagens de confirmação de agendamento não estão sendo enviadas pelo WhatsApp.', 'open', 'medium', 'whatsapp', 'client_portal', NULL, 'Studio Hair', fake_user, 'Ana Costa', 'ana@email.com', true, false, now() - INTERVAL '3 hours'),
    (t4,  'Erro ao emitir NFS-e', 'Ao tentar emitir a nota fiscal, aparece erro "município não aderido".', 'waiting_client', 'high', 'nfse', 'client_portal', NULL, 'Clínica Estética VIP', fake_user, 'Carlos Oliveira', 'carlos@email.com', false, true, now() - INTERVAL '6 hours'),
    (t5,  'Não consigo acessar minha conta', 'Esqueci a senha e o e-mail de recuperação não chega.', 'open', 'high', 'account', 'email', NULL, 'Barbearia Premium', fake_user, 'Pedro Lima', 'pedro@email.com', true, false, now() - INTERVAL '30 minutes'),
    (t6,  'Como alterar plano de assinatura?', 'Quero fazer upgrade do plano Start para o Plus.', 'resolved', 'low', 'other', 'client_portal', NULL, 'Salão da Rê', fake_user, 'Renata Souza', 'renata@email.com', false, false, now() - INTERVAL '3 days'),
    (t7,  'Cartão de crédito recusado', 'Tentei pagar com cartão de crédito e dá erro "transação não autorizada".', 'open', 'high', 'payment', 'client_portal', NULL, 'Barber Shop Elite', fake_user, 'Lucas Ferreira', 'lucas@email.com', true, false, now() - INTERVAL '1 hour'),
    (t8,  'Horários não aparecem para clientes', 'Meus clientes dizem que não veem horários disponíveis na página de agendamento.', 'in_progress', 'critical', 'scheduling', 'whatsapp', NULL, 'Studio Beleza Total', fake_user, 'Fernanda Mendes', 'fernanda@email.com', false, true, now() - INTERVAL '45 minutes'),
    (t9,  'Relatório financeiro zerado', 'O relatório financeiro do mês mostra R$ 0,00 mesmo tendo vários atendimentos.', 'open', 'medium', 'payment', 'client_portal', NULL, 'Espaço Zen Hair', fake_user, 'Roberto Alves', 'roberto@email.com', true, false, now() - INTERVAL '5 hours'),
    (t10, 'Integração WhatsApp caiu', 'A integração com WhatsApp parou de funcionar desde ontem à noite.', 'in_progress', 'high', 'whatsapp', 'client_portal', NULL, 'Salão Glamour', fake_user, 'Patricia Rocha', 'patricia@email.com', true, false, now() - INTERVAL '12 hours'),
    (t11, 'Cancelar NFS-e emitida por engano', 'Emiti uma NFS-e para o cliente errado e preciso cancelar.', 'open', 'high', 'nfse', 'client_portal', NULL, 'Barbearia Vintage', fake_user, 'Marcos Dias', 'marcos@email.com', true, false, now() - INTERVAL '2 hours'),
    (t12, 'Funcionário não consegue logar', 'Cadastrei um funcionário mas ele não consegue acessar o sistema.', 'waiting_client', 'medium', 'account', 'manual', NULL, 'Hair Design Studio', fake_user, 'Juliana Pereira', 'juliana@email.com', false, true, now() - INTERVAL '1 day'),
    (t13, 'Sugestão: campo de observação no agendamento', 'Seria ótimo poder adicionar uma observação no agendamento para anotar preferências do cliente.', 'closed', 'low', 'other', 'client_portal', NULL, 'Salão Encanto', fake_user, 'Amanda Gomes', 'amanda@email.com', false, false, now() - INTERVAL '7 days'),
    (t14, 'Taxa do cartão errada', 'A taxa do cartão está sendo calculada como 5% mas deveria ser 3.5%.', 'open', 'high', 'payment', 'client_portal', NULL, 'Espaço Beauty', fake_user, 'Diego Martins', 'diego@email.com', true, false, now() - INTERVAL '4 hours'),
    (t15, 'Cliente não recebe lembrete', 'Os clientes não estão recebendo o lembrete 24h antes do agendamento.', 'in_progress', 'medium', 'whatsapp', 'email', NULL, 'Studio Corte & Arte', fake_user, 'Camila Ribeiro', 'camila@email.com', false, false, now() - INTERVAL '2 days');

  -- Seed messages for several tickets (both sides)
  INSERT INTO public.ticket_messages (ticket_id, author_id, author_name, author_role, body, is_internal, created_at) VALUES
    -- Ticket 1: client + support
    (t1, fake_user, 'João Silva', 'client', 'Fiz o PIX às 14h e até agora não confirmou. Segue comprovante em anexo.', false, now() - INTERVAL '2 hours'),
    (t1, fake_user, 'Suporte MarkaAI', 'support', 'Olá João! Vamos verificar o status do seu pagamento. Pode informar o ID da transação?', false, now() - INTERVAL '1 hour 30 minutes'),
    (t1, fake_user, 'Suporte MarkaAI', 'admin', 'Verificar no painel do Mercado Pago se o webhook falhou.', true, now() - INTERVAL '1 hour 25 minutes'),

    -- Ticket 2: ongoing conversation
    (t2, fake_user, 'Maria Santos', 'client', 'O agendamento duplicado é para o dia 15/04, horários 10h e 10h.', false, now() - INTERVAL '1 day'),
    (t2, fake_user, 'Suporte MarkaAI', 'support', 'Maria, identificamos o problema. Vou remover o duplicado agora.', false, now() - INTERVAL '23 hours'),
    (t2, fake_user, 'Maria Santos', 'client', 'Obrigada! Pode verificar se não tem outros duplicados?', false, now() - INTERVAL '22 hours'),

    -- Ticket 4: waiting client
    (t4, fake_user, 'Carlos Oliveira', 'client', 'Está dando erro ao emitir NFS-e. O código do município é 3132404.', false, now() - INTERVAL '6 hours'),
    (t4, fake_user, 'Suporte MarkaAI', 'support', 'Carlos, o município 3132404 ainda não aderiu ao sistema nacional de NFS-e. Verifique se há um portal próprio da prefeitura. Aguardamos retorno.', false, now() - INTERVAL '5 hours'),

    -- Ticket 5: urgent account issue
    (t5, fake_user, 'Pedro Lima', 'client', 'Já tentei 3 vezes e o e-mail de recuperação não chega. Verifiquei spam também.', false, now() - INTERVAL '30 minutes'),

    -- Ticket 8: critical with internal note
    (t8, fake_user, 'Fernanda Mendes', 'client', 'Meus clientes estão reclamando que não conseguem agendar. Estou perdendo clientes!', false, now() - INTERVAL '45 minutes'),
    (t8, fake_user, 'Suporte MarkaAI', 'support', 'Fernanda, já identificamos o problema e estamos corrigindo. Deve normalizar em breve.', false, now() - INTERVAL '30 minutes'),
    (t8, fake_user, 'Suporte MarkaAI', 'admin', 'Bug no availability_utils: horário de almoço não sendo excluído corretamente. Fix em andamento.', true, now() - INTERVAL '28 minutes'),

    -- Ticket 6: resolved conversation
    (t6, fake_user, 'Renata Souza', 'client', 'Como faço para mudar meu plano?', false, now() - INTERVAL '3 days'),
    (t6, fake_user, 'Suporte MarkaAI', 'support', 'Renata, acesse Configurações > Assinatura > Alterar Plano. Lá você pode escolher o Plus.', false, now() - INTERVAL '2 days 22 hours'),
    (t6, fake_user, 'Renata Souza', 'client', 'Consegui! Muito obrigada!', false, now() - INTERVAL '2 days 20 hours');

  -- Seed some tags
  INSERT INTO public.ticket_tags (name, color) VALUES
    ('bug', '#EF4444'),
    ('feature-request', '#3B82F6'),
    ('urgente', '#F59E0B'),
    ('documentação', '#8B5CF6'),
    ('financeiro', '#10B981'),
    ('integração', '#F97316')
  ON CONFLICT (name) DO NOTHING;

  RAISE NOTICE 'Support tickets seed data inserted successfully';
END $$;
