-- Migration 169: Adiciona campo de prioridade de escala aos profissionais
-- Permite configurar a ordem de prioridade para auto-seleção de profissionais
-- quando o cliente não escolhe (ou quando o sistema auto-atribui).
-- Menor número = maior prioridade. Default 0.

ALTER TABLE public.employees
ADD COLUMN IF NOT EXISTS schedule_priority INTEGER NOT NULL DEFAULT 0;

-- Índice para ordenação eficiente por prioridade dentro de cada loja
CREATE INDEX IF NOT EXISTS idx_employees_shop_priority
  ON public.employees (shop_id, schedule_priority ASC);

COMMENT ON COLUMN public.employees.schedule_priority IS
  'Ordem de prioridade para escala automática. Menor valor = maior prioridade. Configurável via drag-and-drop na página de equipe.';
