-- 100_add_unique_constraint_to_slugs.sql
-- Garante que slugs sejam únicos na tabela shops

ALTER TABLE public.shops ADD CONSTRAINT shops_slug_unique UNIQUE (slug);
