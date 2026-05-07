-- Migration: 163_fix_appointments_client_name_from_email.sql
-- Corrige registros onde client_name foi salvo com o email do cliente
-- ao invés do nome real. Usa users.name como fonte de verdade.

UPDATE appointments a
SET client_name = u.name
FROM users u
WHERE a.client_id = u.id::text
  AND a.client_name LIKE '%@%'          -- client_name parece ser um email
  AND a.client_name NOT LIKE '% %'      -- emails não têm espaço (exclui "João email@x.com")
  AND u.name IS NOT NULL
  AND trim(u.name) <> ''
  AND trim(u.name) NOT LIKE '%@%';      -- garante que users.name também não é email

-- Registros onde o usuário também não tem nome: mantém 'Cliente' como fallback
UPDATE appointments
SET client_name = 'Cliente'
WHERE client_name LIKE '%@%'
  AND client_name NOT LIKE '% %';
