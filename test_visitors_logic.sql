-- Test script para validar a lógica de visitantes vs clientes
-- Execute no SQL Editor do Supabase

-- 1. Verificar se há dados na tabela shop_views
SELECT 
    'shop_views' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT shop_id) as unique_shops
FROM shop_views;

-- 2. Verificar se há dados na tabela favorites
SELECT 
    'favorites' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT shop_id) as unique_shops
FROM favorites;

-- 3. Verificar se há dados na tabela appointments
SELECT 
    'appointments' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT client_id) as unique_clients,
    COUNT(DISTINCT shop_id) as unique_shops
FROM appointments;

-- 4. Simular a lógica atual do código para um shop específico
-- Substitua 'SEU_SHOP_ID' por um ID real
WITH all_interactions AS (
  -- Visitantes (shop_views)
  SELECT 
    sv.user_id,
    sv.shop_id,
    0 as agendamentos_count,
    TRUE as is_visitor,
    FALSE as is_favorite,
    'visitor' as interaction_type
  FROM shop_views sv
  
  UNION ALL
  
  -- Favoritos (favorites)
  SELECT 
    f.user_id,
    f.shop_id,
    0 as agendamentos_count,
    FALSE as is_visitor,
    TRUE as is_favorite,
    'favorite' as interaction_type
  FROM favorites f
  
  UNION ALL
  
  -- Clientes (appointments)
  SELECT 
    a.client_id as user_id,
    a.shop_id,
    COUNT(*) as agendamentos_count,
    FALSE as is_visitor,
    FALSE as is_favorite,
    'appointment' as interaction_type
  FROM appointments a
  GROUP BY a.client_id, a.shop_id
),
consolidated AS (
  SELECT 
    user_id,
    shop_id,
    SUM(agendamentos_count) as total_agendamentos,
    BOOL_OR(is_visitor) as has_viewed,
    BOOL_OR(is_favorite) as has_favorited,
    STRING_AGG(DISTINCT interaction_type, ', ') as interaction_types
  FROM all_interactions
  GROUP BY user_id, shop_id
),
classified AS (
  SELECT 
    user_id,
    shop_id,
    total_agendamentos,
    has_viewed,
    has_favorited,
    interaction_types,
    CASE 
      WHEN total_agendamentos > 0 THEN 'CLIENTE'
      ELSE 'VISITANTE'
    END as classification
  FROM consolidated
)
SELECT 
    classification,
    COUNT(*) as count,
    COUNT(CASE WHEN has_viewed THEN 1 END) as viewed_count,
    COUNT(CASE WHEN has_favorited THEN 1 END) as favorited_count,
    AVG(total_agendamentos) as avg_appointments,
    STRING_AGG(interaction_types, '; ') as interaction_examples
FROM classified
WHERE shop_id = 'SEU_SHOP_ID'  -- <-- SUBSTITUA POR UM SHOP ID REAL
GROUP BY classification
ORDER BY classification;

-- 5. Verificar exemplos específicos para um shop
SELECT 
    c.classification,
    c.total_agendamentos,
    c.has_viewed,
    c.has_favorited,
    c.interaction_types,
    u.name,
    u.email,
    u.phone
FROM classified c
LEFT JOIN users u ON c.user_id = u.id
WHERE c.shop_id = 'SEU_SHOP_ID'  -- <-- SUBSTITUA POR UM SHOP ID REAL
ORDER BY 
    CASE WHEN c.total_agendamentos > 0 THEN 0 ELSE 1 END,
    c.total_agendamentos DESC
LIMIT 10;
