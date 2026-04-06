-- Debug script para verificar dados de shop_views
-- Execute no SQL Editor do Supabase

-- 1. Verificar se há dados na tabela shop_views
SELECT COUNT(*) as total_views, 
       COUNT(DISTINCT user_id) as unique_visitors,
       COUNT(DISTINCT shop_id) as shops_with_views
FROM shop_views;

-- 2. Verificar views por shop (exemplo)
SELECT 
    shop_id,
    COUNT(*) as total_views,
    COUNT(DISTINCT user_id) as unique_visitors,
    MAX(viewed_at) as last_view
FROM shop_views 
GROUP BY shop_id
ORDER BY total_views DESC
LIMIT 10;

-- 3. Verificar dados de visitantes vs clientes para um shop específico
-- Substitua 'SHOP_ID_AQUI' por um ID real de shop
WITH visitor_data AS (
  SELECT 
    sv.user_id,
    sv.viewed_at,
    u.name,
    u.email,
    u.phone,
    'visitor' as type
  FROM shop_views sv
  LEFT JOIN users u ON sv.user_id = u.id
  WHERE sv.shop_id = 'SHOP_ID_AQUI'
),
client_data AS (
  SELECT 
    a.client_id as user_id,
    a.scheduled_at,
    u.name,
    u.email,
    u.phone,
    'client' as type
  FROM appointments a
  LEFT JOIN users u ON a.client_id = u.id
  WHERE a.shop_id = 'SHOP_ID_AQUI'
  AND a.status IN ('concluido', 'pago')
),
favorite_data AS (
  SELECT 
    f.user_id,
    f.created_at as viewed_at,
    u.name,
    u.email,
    u.phone,
    'favorite' as type
  FROM favorites f
  LEFT JOIN users u ON f.user_id = u.id
  WHERE f.shop_id = 'SHOP_ID_AQUI'
)
SELECT * FROM visitor_data
UNION ALL
SELECT * FROM client_data  
UNION ALL
SELECT * FROM favorite_data
ORDER BY viewed_at DESC
LIMIT 20;

-- 4. Verificar a lógica atual de separação (simulando o código)
WITH all_interactions AS (
  SELECT 
    sv.user_id,
    MAX(sv.viewed_at) as last_viewed,
    0 as agendamentos_count,
    FALSE as is_favorite,
    TRUE as is_visitor
  FROM shop_views sv
  WHERE sv.shop_id = 'SHOP_ID_AQUI'
  GROUP BY sv.user_id
  
  UNION ALL
  
  SELECT 
    a.client_id as user_id,
    NULL::timestamptz as last_viewed,
    COUNT(*) as agendamentos_count,
    FALSE as is_favorite,
    FALSE as is_visitor
  FROM appointments a
  WHERE a.shop_id = 'SHOP_ID_AQUI'
  GROUP BY a.client_id
  
  UNION ALL
  
  SELECT 
    f.user_id,
    NULL::timestamptz as last_viewed,
    0 as agendamentos_count,
    TRUE as is_favorite,
    FALSE as is_visitor
  FROM favorites f
  WHERE f.shop_id = 'SHOP_ID_AQUI'
  GROUP BY f.user_id
),
final_data AS (
  SELECT 
    user_id,
    MAX(last_viewed) as last_viewed,
    SUM(agendamentos_count) as agendamentos_count,
    BOOL_OR(is_favorite) as is_favorite,
    BOOL_OR(is_visitor) as is_visitor,
    CASE 
      WHEN SUM(agendamentos_count) > 0 OR BOOL_OR(is_favorite) = TRUE THEN 'client'
      ELSE 'visitor'
    END as classification
  FROM all_interactions
  GROUP BY user_id
)
SELECT 
  classification,
  COUNT(*) as count,
  agendamentos_count,
  is_favorite,
  is_visitor
FROM final_data
GROUP BY classification, agendamentos_count, is_favorite, is_visitor
ORDER BY classification;
