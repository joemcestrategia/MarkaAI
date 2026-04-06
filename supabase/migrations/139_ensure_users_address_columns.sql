-- 139_ensure_users_address_columns.sql
-- Ensures all address-related columns exist in public.users.
-- These columns are used by client_register_page.dart (upsert) and by
-- the handle_new_user trigger (migrations 135/136) but were never added
-- via a migration — only via the Dashboard in some environments.
-- This migration makes the schema explicit and portable.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='zip_code') THEN
        ALTER TABLE public.users ADD COLUMN zip_code TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='street') THEN
        ALTER TABLE public.users ADD COLUMN street TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='neighborhood') THEN
        ALTER TABLE public.users ADD COLUMN neighborhood TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='city') THEN
        ALTER TABLE public.users ADD COLUMN city TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='state') THEN
        ALTER TABLE public.users ADD COLUMN state TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='number') THEN
        ALTER TABLE public.users ADD COLUMN number TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='verified') THEN
        ALTER TABLE public.users ADD COLUMN verified BOOLEAN DEFAULT false;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='role') THEN
        -- role may exist as 'tipo' — rename if so, otherwise add fresh
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='tipo') THEN
            ALTER TABLE public.users RENAME COLUMN tipo TO role;
        ELSE
            ALTER TABLE public.users ADD COLUMN role TEXT DEFAULT 'cliente';
        END IF;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='plan') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='users' AND column_name='plano') THEN
            ALTER TABLE public.users RENAME COLUMN plano TO plan;
        ELSE
            ALTER TABLE public.users ADD COLUMN plan TEXT DEFAULT 'free';
        END IF;
    END IF;
END $$;
