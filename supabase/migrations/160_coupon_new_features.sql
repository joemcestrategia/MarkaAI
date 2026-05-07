-- Migration 160: Novas features de cupons (público-alvo, classificações bloqueadas, métodos de pagamento)
-- Todos os campos com DEFAULT seguros — cupons existentes continuam funcionando igual

-- Feature A: público-alvo do cupom
ALTER TABLE coupons
ADD COLUMN IF NOT EXISTS target_audience TEXT
  NOT NULL DEFAULT 'all'
  CHECK (target_audience IN ('all', 'new_clients', 'vip_only'));

-- Feature B: categorias de clientes bloqueadas de usar o cupom
ALTER TABLE coupons
ADD COLUMN IF NOT EXISTS blocked_classifications TEXT[]
  NOT NULL DEFAULT '{}';

-- Feature C: métodos de pagamento válidos (array vazio = todos)
ALTER TABLE coupons
ADD COLUMN IF NOT EXISTS valid_payment_methods TEXT[]
  NOT NULL DEFAULT '{}';

-- Comentários descritivos para documentação
COMMENT ON COLUMN coupons.target_audience IS 'Público-alvo: all (todos), new_clients (apenas novos), vip_only (apenas VIPs)';
COMMENT ON COLUMN coupons.blocked_classifications IS 'Classificações/tags de clientes que NÃO podem usar este cupom';
COMMENT ON COLUMN coupons.valid_payment_methods IS 'Métodos de pagamento aceitos (ex: [pix, card]). Array vazio = qualquer método';
